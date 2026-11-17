import {
  BadRequestException,
  Body,
  Controller,
  Post,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from "@nestjs/common";
import { FileInterceptor } from "@nestjs/platform-express";
import { SkipThrottle } from "@nestjs/throttler";
import { memoryStorage } from "multer";
import { Public } from "../../../common/decorators/public.decorator";
import { UploadsService } from "../../uploads/application/uploads.service";
import { SpeechToTextService } from "../application/speech-to-text.service";
import type { AuthenticatedLeadUser } from "../domain/lead-collection.types";
import { CurrentLeadAgent } from "./decorators/current-lead-agent.decorator";
import { LeadAgentGuard } from "./guards/lead-agent.guard";

@Public()
@UseGuards(LeadAgentGuard)
@SkipThrottle({ default: true, ipAbuse: true })
@Controller("lead-collection/agent/voice")
export class LeadVoiceController {
  constructor(
    private readonly uploads: UploadsService,
    private readonly stt: SpeechToTextService,
  ) {}

  @Post("transcribe")
  @UseInterceptors(
    FileInterceptor("file", {
      storage: memoryStorage(),
      limits: { fileSize: 15 * 1024 * 1024 }, // 15MB audio limit
    }),
  )
  async transcribe(
    @CurrentLeadAgent() agent: AuthenticatedLeadUser,
    @UploadedFile() file: Express.Multer.File,
    @Body("type") type?: string,
    @Body("duration") durationStr?: string,
    @Body("leadId") leadId?: string,
  ) {
    if (!file) {
      throw new BadRequestException('No audio file provided (form field "file")');
    }

    const duration = parseFloat(durationStr || "0") || 0;

    // 1. Upload audio securely to Cloudinary / storage
    let audioUrl = "";
    try {
      const uploadRes = await this.uploads.upload(file, "lead-voice-notes", {
        allowedKinds: ["audio"],
      });
      audioUrl = uploadRes?.url || "";
    } catch (err: any) {
      // Fallback: If cloudinary upload fails or is unavailable, use data URL or report
      audioUrl = "";
    }

    // 2. Transcribe speech to text using AI service
    const promptContext =
      type === "internal"
        ? "Transcribe internal field agent observations regarding property verification, infrastructure, road access, and feasibility."
        : "Transcribe meeting and discussion notes between the field agent and property owner regarding tariff, facilities, and partnership.";

    const sttResult = await this.stt.transcribeAudio(file, { promptContext });

    return {
      success: true,
      message: "Audio transcribed successfully",
      data: {
        audioUrl,
        transcript: sttResult.transcript,
        provider: sttResult.provider,
        duration,
        recordedAt: new Date().toISOString(),
        agentId: agent.id,
        agentName: agent.name,
        type: type || "meeting",
        leadId: leadId || "",
      },
    };
  }
}
