data "yandex_client_config" "client" {}

###########
## Registry
###########
resource "yandex_container_registry" "this" {
  name      = var.registry
  folder_id = data.yandex_client_config.client.folder_id

  labels = var.labels == null ? { project = var.registry } : var.labels
}

resource "yandex_container_registry_iam_binding" "this" {
  for_each = length(var.members) > 0 ? { "main" = true } : {}
  
  registry_id = yandex_container_registry.this.id
  role        = "container-registry.images.${var.role}"
  members     = toset(var.members)
}

#############
## Repository
#############
resource "yandex_container_repository" "this" {
  for_each = var.repos
  name     = "${yandex_container_registry.this.id}/${each.key}"
}

# IAM binding for repositories with specific access requirements
resource "yandex_container_repository_iam_binding" "this" {
  for_each = {
    for k, v in var.repos : k => v
    if length(lookup(v, "members", [])) > 0
  }

  repository_id = yandex_container_repository.this[each.key].id
  role          = "container-registry.images.${lookup(each.value, "role", "puller")}"
  members       = toset(lookup(each.value, "members", []))
}

locals {
  # Filter repositories that have lifecycle policies configured
  repos_with_policies = {
    for repo_key, repo in var.repos : repo_key => repo
    if lookup(repo, "lifecycle_policy", null) != null
  }
}

resource "yandex_container_repository_lifecycle_policy" "this" {
  for_each = local.repos_with_policies

  # Policy configuration with sensible defaults
  name        = lookup(each.value.lifecycle_policy, "name", "policy-${each.key}")
  status      = lookup(each.value.lifecycle_policy, "status", "active")
  description = lookup(each.value.lifecycle_policy, "description", "Lifecycle policy for ${each.key} repository")
  
  repository_id = yandex_container_repository.this[each.key].id

  # Lifecycle rules configuration
  # Supports both array of rules and single rule formats
  dynamic "rule" {
    for_each = lookup(each.value.lifecycle_policy, "rules", null) != null ? (
      each.value.lifecycle_policy.rules
    ) : (
      [each.value.lifecycle_policy]
    )
    
    content {
      description   = lookup(rule.value, "description", "")
      expire_period = lookup(rule.value, "expire_period", null)
      untagged      = lookup(rule.value, "untagged", false)
      tag_regexp    = lookup(rule.value, "tag_regexp", ".*")
      retained_top  = lookup(rule.value, "retained_top", null)
    }
  }
}
