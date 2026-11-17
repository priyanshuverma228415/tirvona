import { IsEmail, IsOptional, IsString, MaxLength, MinLength } from "class-validator";

export class LeadLoginDto {
  @IsString() @MinLength(10) @MaxLength(20) phone!: string;
  @IsString() @MinLength(6) @MaxLength(128) password!: string;
}

export class LeadRegisterDto {
  @IsString() @MinLength(2) @MaxLength(120) name!: string;
  @IsString() @MinLength(10) @MaxLength(20) phone!: string;
  @IsOptional() @IsEmail() @MaxLength(160) email?: string;
  @IsString() @MinLength(8) @MaxLength(128) password!: string;
  @IsString() @MinLength(2) @MaxLength(120) state!: string;
  @IsString() @MinLength(2) @MaxLength(120) district!: string;
}
