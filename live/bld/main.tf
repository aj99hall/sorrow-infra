data "google_project" "current" {
  project_id = "build-000"
}

output "project_number" {
  value = {
    id     = data.google_project.current.project_id
    number = data.google_project.current.number
    name   = data.google_project.current.name
  }
}