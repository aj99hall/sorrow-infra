resource "google_storage_bucket" "first_bucket" {
  name                        = "first_bucket_ds6f83x"
  location                    = var.region
  uniform_bucket_level_access = true
}


resource "google_storage_bucket" "gha_test" {
  name                        = "sorrow-bld-gha-test-001"
  location                    = var.region
  uniform_bucket_level_access = true

  force_destroy = false

  labels = {
    managed_by = "terraform"
    env        = "bld"
    purpose    = "gha-test"
  }
}