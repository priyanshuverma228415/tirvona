import { Body, Controller, Get, HttpCode, Post, Put, UseGuards } from "@nestjs/common";
import { ApiTags } from "@nestjs/swagger";
import { SkipThrottle } from "@nestjs/throttler";
import { Public } from "../../../common/decorators/public.decorator";
import { LeadAuthService } from "../application/lead-auth.service";
import { LeadUsersService } from "../application/lead-users.service";
import type { AuthenticatedLeadUser } from "../domain/lead-collection.types";
import { CurrentLeadAgent } from "./decorators/current-lead-agent.decorator";
import { LeadLoginDto, LeadRegisterDto } from "./dtos/lead-auth.dto";
import { LeadAgentGuard } from "./guards/lead-agent.guard";

@ApiTags("Lead Collection")
@Public()
@SkipThrottle({ default: true, ipAbuse: true })
@Controller("lead-collection/auth")
export class LeadAuthController {
  constructor(
    private readonly auth: LeadAuthService,
    private readonly leadUsers: LeadUsersService,
  ) {}

  @Post("login")
  @HttpCode(200)
  async login(@Body() dto: LeadLoginDto) {
    return { success: true, data: await this.auth.login(dto) };
  }

  @Post("register")
  @HttpCode(201)
  async register(@Body() dto: LeadRegisterDto) {
    const user = await this.auth.register(dto);
    return {
      success: true,
      message:
        "Registration submitted successfully! Your account is pending admin approval.",
      data: user,
    };
  }

  @Get("me")
  @UseGuards(LeadAgentGuard)
  me(@CurrentLeadAgent() agent: AuthenticatedLeadUser) {
    return { success: true, data: agent };
  }

  @Put("me")
  @UseGuards(LeadAgentGuard)
  async updateProfile(
    @CurrentLeadAgent() agent: AuthenticatedLeadUser,
    @Body() dto: { name?: string; email?: string; phone?: string },
  ) {
    const updated = await this.leadUsers.update(agent.id, dto);
    return {
      success: true,
      message: "Profile updated successfully",
      data: {
        id: updated._id.toString(),
        name: updated.name,
        phone: updated.phone,
        email: updated.email ?? "",
        role: updated.role,
        status: updated.status,
        region: updated.region ?? "",
        state: (updated as any).state ?? "",
        district: (updated as any).district ?? "",
        employeeCode: updated.employeeCode ?? "",
      },
    };
  }
}
