/*resource "google_storage_bucket" "gha_test" {
  name                        = "sorrow-bld-gha-test-001"
  location                    = "EU"
  uniform_bucket_level_access = true

  force_destroy = false

  labels = {
    managed_by = "terraform"
    env        = "bld"
    purpose    = "gha-test"
  }
}*/