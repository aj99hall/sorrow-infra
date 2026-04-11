data "google_project" "current" {
  project_id = var.project_id
}

output "project_number" {
  value = {
    id     = data.google_project.current.project_id
    number = data.google_project.current.number
    name   = data.google_project.current.name
  }
}