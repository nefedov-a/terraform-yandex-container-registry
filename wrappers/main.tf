module "wrapper" {
  source = "../"

  for_each = var.items

  registry = try(each.value.registry, var.defaults.registry, null)
  labels   = try(each.value.labels, var.defaults.labels, {})
  members  = try(each.value.members, var.defaults.members, [])
  role     = try(each.value.role, var.defaults.role, "puller")
  repos    = try(each.value.repos, var.defaults.repos, {})
}
