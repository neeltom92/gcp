terraform {
  backend "gcs" {
    bucket = "neel-test"
    prefix = "terraform/gke/state"
  }
}

provider "google" {
  credentials = file("/Users/neelthomas/.config/gcloud/legacy_credentials/learnusa92@gmail.com/adc.json")
  project     = "neel-test-399301"
  region      = "us-west1"
}

# Create VPC
resource "google_compute_network" "vpc" {
  name                    = "vpc1"
  auto_create_subnetworks = false
}

# Create Subnet
resource "google_compute_subnetwork" "subnet" {
  name          = "subnet1"
  region        = "us-west1"
  network       = google_compute_network.vpc.name
  ip_cidr_range = "10.0.0.0/24"
}

resource "google_container_cluster" "primary" {
  name                     = "my-gke-cluster"
  location                 = "us-west1-a"
  network                  = google_compute_network.vpc.name
  subnetwork               = google_compute_subnetwork.subnet.name
  remove_default_node_pool = true
  initial_node_count       = 1

  private_cluster_config {
    enable_private_endpoint = true
    enable_private_nodes    = true
    master_ipv4_cidr_block  = "10.13.0.0/28"
  }

  ip_allocation_policy {
    cluster_ipv4_cidr_block  = "10.11.0.0/21"
    services_ipv4_cidr_block = "10.12.0.0/21"
  }

  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "10.0.0.7/32"
      display_name = "net1"
    }
  }
}

# Create managed node pool
resource "google_container_node_pool" "primary_nodes" {
  name       = google_container_cluster.primary.name
  location   = "us-west1-a"
  cluster    = google_container_cluster.primary.name
  node_count = 1

  node_config {
    oauth_scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
    ]

    labels = {
      env = "dev"
    }

    machine_type = "n1-standard-1"
    preemptible  = true

    metadata = {
      disable-legacy-endpoints = "true"
    }
  }
}

resource "google_compute_address" "my_internal_ip_addr" {
  project      = "neel-test-399301"
  address_type = "INTERNAL"
  region       = "us-west1"
  subnetwork   = "subnet1"
  name         = "my-ip"
  address      = "10.0.0.7"
  description  = "An internal IP address for my jump host"
}

resource "google_compute_instance" "default" {
  project      = "neel-test-399301"
  zone         = "us-west1-a"
  name         = "jump-host"
  machine_type = "e2-medium"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }

  network_interface {
    network    = "vpc1"
    subnetwork = "subnet1"
    network_ip = google_compute_address.my_internal_ip_addr.address
  }
}

resource "google_compute_firewall" "rules" {
  project = "neel-test-399301"
  name    = "allow-ssh"
  network = "vpc1"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
}

resource "google_project_iam_member" "project" {
  project = "neel-test-399301"
  role    = "roles/iap.tunnelResourceAccessor"
  member  = "serviceAccount:neel-test2@neel-test-399301.iam.gserviceaccount.com"

}

# Create a cloud router for NAT gateway
resource "google_compute_router" "router" {
  project = "neel-test-399301"
  name    = "nat-router"
  network = "vpc1"
  region  = "us-west1"
}

module "cloud-nat" {
  source     = "terraform-google-modules/cloud-nat/google"
  version    = "~> 1.2"
  project_id = "neel-test-399301"
  region     = "us-west1"
  router     = google_compute_router.router.name
  name       = "nat-config"
}

############ Output ############################################

output "kubernetes_cluster_host" {
  value       = google_container_cluster.primary.endpoint
  description = "GKE Cluster Host"
}

output "kubernetes_cluster_name" {
  value       = google_container_cluster.primary.name
  description = "GKE Cluster Name"
}
