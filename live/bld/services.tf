locals {
  project_services = toset([
    "cloudresourcemanager.googleapis.com",
    "serviceusage.googleapis.com",
    "storage.googleapis.com",
    "bigquery.googleapis.com",
    "datacatalog.googleapis.com",
    "cloudasset.googleapis.com",

  ])
}

resource "google_project_service" "project_services" {
  for_each = local.project_services

  project = "build-000"
  service = each.value

  disable_on_destroy = false
}