variable "registry" {
  description = "Container registry name"
  type        = string
}

variable "labels" {
  description = "Container registry labels"
  type        = map(string)
  default     = {}
}

# see https://registry.terraform.io/providers/yandex-cloud/yandex/latest/docs/resources/container_registry_iam_binding
variable "members" {
  description = "The role that should be applied"
  type        = list(string)
  default     = ["system:allUsers"]
}

# see https://cloud.yandex.com/en/docs/container-registry/security/
variable "role" {
  description = "The role that should be applied"
  type        = string
  default     = "puller"

  validation {
    condition     = contains(["puller", "pusher", "admin"], var.role)
    error_message = "Role must be one of `puller`, `pusher` or `admin`."
  }
}

variable "repos" {
  description = "Repositories with role binding and lifecycle_policy"
  type = map(object({
    members = optional(list(string), [])
    role    = optional(string, "puller")
    lifecycle_policy = optional(object({
      name        = optional(string)
      status      = optional(string, "active")
      description = optional(string)
      rules = optional(list(object({
        description   = optional(string, "")
        expire_period = optional(string)        # Must be multiple of 24h (e.g., "24h", "48h")
        retained_top  = optional(number)        # Number of images to retain
        untagged      = optional(bool, false)   # Apply to untagged images
        tag_regexp    = optional(string, ".*")  # Ignored when untagged=true
      })), [])
      # Legacy format support - rule parameters directly in lifecycle_policy
      expire_period = optional(string)
      retained_top  = optional(number)
      untagged      = optional(bool)
      tag_regexp    = optional(string)
    }))
  }))
  default = {}

  validation {
    condition = alltrue([
      for repo_key, repo in var.repos : (
        lookup(repo, "role", "puller") == null ? true : 
        contains(["puller", "pusher", "admin"], repo.role)
      )
    ])
    error_message = "Repository role must be one of: puller, pusher, admin."
  }

  validation {
    condition = alltrue([
      for repo_key, repo in var.repos : (
        lookup(repo, "lifecycle_policy", null) == null ? true :
        alltrue([
          for rule in lookup(repo.lifecycle_policy, "rules", [repo.lifecycle_policy]) : (
            lookup(rule, "expire_period", null) != null || lookup(rule, "retained_top", null) != null
          )
        ])
      )
    ])
    error_message = "Each lifecycle rule must have either expire_period or retained_top (or both) specified."
  }

  validation {
    condition = alltrue([
      for repo_key, repo in var.repos : (
        lookup(repo, "lifecycle_policy", null) == null ? true :
        alltrue([
          for rule in lookup(repo.lifecycle_policy, "rules", [repo.lifecycle_policy]) : (
            lookup(rule, "expire_period", null) == null ? true :
            can(regex("^[0-9]+h$", rule.expire_period)) && parseint(replace(rule.expire_period, "h", ""), 10) % 24 == 0
          )
        ])
      )
    ])
    error_message = "expire_period must be in format 'Nh' where N is a multiple of 24 (e.g., '24h', '48h', '168h')."
  }

  validation {
    condition = alltrue([
      for repo_key, repo in var.repos : (
        lookup(repo, "lifecycle_policy", null) == null ? true :
        contains(["active", "disabled"], lookup(repo.lifecycle_policy, "status", "active"))
      )
    ])
    error_message = "lifecycle_policy status must be either 'active' or 'disabled'."
  }

  validation {
    condition = alltrue([
      for repo_key, repo in var.repos : (
        lookup(repo, "lifecycle_policy", null) == null ? true :
        alltrue([
          for rule in lookup(repo.lifecycle_policy, "rules", [repo.lifecycle_policy]) : (
            # When untagged=true, tag_regexp should not be specified (API ignores it)
            lookup(rule, "untagged", false) == true ? (
              lookup(rule, "tag_regexp", ".*") == ".*" || lookup(rule, "tag_regexp", null) == null
            ) : true
          )
        ])
      )
    ])
    error_message = "When untagged=true, tag_regexp is ignored by the API. Either set untagged=false to use tag_regexp, or remove tag_regexp when targeting untagged images."
  }
}
