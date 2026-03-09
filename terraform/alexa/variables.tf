variable "home_assistant_url" {
  description = "The externally reachable Home Assistant URL"
  type        = string
  default     = "https://ha.pitower.link"
}

variable "alexa_skill_id" {
  description = "The Alexa Smart Home Skill ID (amzn1.ask.skill.xxx)"
  type        = string
  default     = "amzn1.ask.skill.c91931eb-3eef-4ac4-9471-1fca38a347e2"
}

variable "debug" {
  description = "Enable debug logging in Lambda"
  type        = bool
  default     = false
}
