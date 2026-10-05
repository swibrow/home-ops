variable "crier_url" {
  description = "The externally reachable garrison crier URL"
  type        = string
  default     = "https://garrison-alexa.wibrow.dev"
}

variable "alexa_skill_id" {
  description = "The garrison Alexa Custom Skill ID (amzn1.ask.skill.xxx)"
  type        = string
  default     = "amzn1.ask.skill.86266b13-7134-4ef7-8d34-1dd0d02faf50"
}

variable "debug" {
  description = "Enable debug logging in Lambda"
  type        = bool
  default     = false
}
