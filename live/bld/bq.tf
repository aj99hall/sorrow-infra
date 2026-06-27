resource "google_bigquery_dataset" "rlsdemo" {
  dataset_id = "rlsdemo"
  location   = var.region
}

resource "google_bigquery_table" "table1" {
  deletion_protection = false

  schema = <<EOF
[
  {
    "name": "customerName",
    "type": "STRING"
  },
  {
    "name": "criminal_record",
    "type": "STRING"
  }
]
EOF

  dataset_id = google_bigquery_dataset.example.dataset_id
  table_id   = "table1"
}

resource "google_bigquery_row_access_policy" "rlspolicy_crim" {
  dataset_id = google_bigquery_dataset.example.dataset_id
  table_id   = google_bigquery_table.example.table_id
  policy_id  = "rlspolicy_crim"

  filter_predicate = "criminal_record is not NULL"
  grantees = [
    "group:gg_psi_ag@sorrow.biz"
  ]
}