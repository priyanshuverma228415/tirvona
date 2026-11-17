import { Injectable, Logger } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";

@Injectable()
export class SpeechToTextService {
  private readonly logger = new Logger(SpeechToTextService.name);

  constructor(private readonly config: ConfigService) {}

  /**
   * Transcribe an audio file buffer to text.
   * Supports Groq Whisper, OpenAI Whisper, and Google Gemini Multimodal STT.
   */
  async transcribeAudio(
    file: Express.Multer.File,
    options?: { language?: string; promptContext?: string },
  ): Promise<{ transcript: string; provider: string; confidence?: number }> {
    const groqKey = process.env.GROQ_API_KEY || this.config.get<string>("groqApiKey");
    const geminiKey = process.env.GEMINI_API_KEY || this.config.get<string>("geminiApiKey");
    const openaiKey = process.env.OPENAI_API_KEY || this.config.get<string>("openaiApiKey");

    // 1. Try Groq Whisper (Fastest & high accuracy for Hindi/English)
    if (groqKey?.trim()) {
      try {
        const text = await this.transcribeWithGroq(file, groqKey.trim(), options?.language);
        if (text) {
          return { transcript: text, provider: "groq-whisper-large-v3" };
        }
      } catch (err: any) {
        this.logger.warn(`Groq STT failed: ${err.message}. Trying next provider...`);
      }
    }

    // 2. Try Google Gemini (Multimodal native audio understanding)
    if (geminiKey?.trim()) {
      try {
        const text = await this.transcribeWithGemini(file, geminiKey.trim(), options?.promptContext);
        if (text) {
          return { transcript: text, provider: "google-gemini" };
        }
      } catch (err: any) {
        this.logger.warn(`Gemini STT failed: ${err.message}. Trying next provider...`);
      }
    }

    // 3. Try OpenAI Whisper
    if (openaiKey?.trim()) {
      try {
        const text = await this.transcribeWithOpenAI(file, openaiKey.trim(), options?.language);
        if (text) {
          return { transcript: text, provider: "openai-whisper-1" };
        }
      } catch (err: any) {
        this.logger.warn(`OpenAI STT failed: ${err.message}.`);
      }
    }

    // Fallback if no external AI STT key configured yet
    const fallbackText =
      `Voice note recorded (${(file.size / 1024).toFixed(1)} KB). Audio preserved. Set GROQ_API_KEY or GEMINI_API_KEY in .env for live AI transcription.`;
    return {
      transcript: fallbackText,
      provider: "local-audio-storage",
    };
  }

  private async transcribeWithGroq(
    file: Express.Multer.File,
    apiKey: string,
    language?: string,
  ): Promise<string> {
    const formData = new FormData();
    const blob = new Blob([new Uint8Array(file.buffer)], {
      type: file.mimetype || "audio/m4a",
    });
    formData.append("file", blob, file.originalname || "recording.m4a");
    // Use turbo model - faster and more accurate for short clips
    formData.append("model", "whisper-large-v3-turbo");
    formData.append("response_format", "verbose_json");
    // Auto-detect Hindi/English - do not force language so both are detected
    // Add a prompt to bias transcription toward verbatim Hindi/English speech
    formData.append(
      "prompt",
      "Field agent verbatim note in Hindi or English. Transcribe exactly word by word.",
    );

    const res = await fetch("https://api.groq.com/openai/v1/audio/transcriptions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
      },
      body: formData,
    });

    if (!res.ok) {
      const errText = await res.text();
      throw new Error(`Groq API returned ${res.status}: ${errText}`);
    }

    const data = (await res.json()) as { text?: string; segments?: Array<{ text: string; no_speech_prob?: number }> };

    // Filter out segments where no_speech_prob is very high (silence / background noise)
    if (data.segments && data.segments.length > 0) {
      const spokenSegments = data.segments.filter(
        (seg) => (seg.no_speech_prob ?? 0) < 0.6,
      );
      if (spokenSegments.length > 0) {
        return spokenSegments.map((s) => s.text).join(" ").trim();
      }
      // All segments were silence — return empty so fallback kicks in
      return "";
    }

    return data.text?.trim() || "";
  }

  private async transcribeWithOpenAI(
    file: Express.Multer.File,
    apiKey: string,
    language?: string,
  ): Promise<string> {
    const formData = new FormData();
    const blob = new Blob([new Uint8Array(file.buffer)], {
      type: file.mimetype || "audio/m4a",
    });
    formData.append("file", blob, file.originalname || "recording.m4a");
    formData.append("model", "whisper-1");
    if (language) {
      formData.append("language", language);
    }

    const res = await fetch("https://api.openai.com/v1/audio/transcriptions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
      },
      body: formData,
    });

    if (!res.ok) {
      const errText = await res.text();
      throw new Error(`OpenAI API returned ${res.status}: ${errText}`);
    }

    const data = (await res.json()) as { text?: string };
    return data.text?.trim() || "";
  }

  private async transcribeWithGemini(
    file: Express.Multer.File,
    apiKey: string,
    promptContext?: string,
  ): Promise<string> {
    const base64Audio = file.buffer.toString("base64");
    const mimeType = file.mimetype || "audio/mp4";

    const prompt =
      "You are a strict speech-to-text transcription engine. Your ONLY job is to write down EXACTLY what the person says in the audio — word for word, in the same language they spoke (Hindi, Hinglish, or English). Do NOT add greetings, summaries, punctuation beyond what was spoken, or any extra words. Do NOT interpret, improve, or paraphrase. Output ONLY the raw spoken words, nothing else.";

    const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=${apiKey}`;

    const res = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [
          {
            parts: [
              { text: prompt },
              {
                inlineData: {
                  mimeType: mimeType.includes("m4a") ? "audio/mp4" : mimeType,
                  data: base64Audio,
                },
              },
            ],
          },
        ],
      }),
    });

    if (!res.ok) {
      const errText = await res.text();
      throw new Error(`Gemini API returned ${res.status}: ${errText}`);
    }

    const data = (await res.json()) as any;
    const candidates = data.candidates;
    if (candidates && candidates.length > 0) {
      const parts = candidates[0].content?.parts;
      if (parts && parts.length > 0) {
        return parts.map((p: any) => p.text || "").join("").trim();
      }
    }
    return "";
  }
}
