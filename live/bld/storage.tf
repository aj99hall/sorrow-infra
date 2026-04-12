resource "google_storage_bucket" "first_bucket" {
  name                        = "first_bucket_ds6f83x"
  location                    = var.region
  uniform_bucket_level_access = true
}