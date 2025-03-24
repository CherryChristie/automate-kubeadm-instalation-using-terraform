variable "kubeadm_key_name" {
  type = string
  description = "name of our keypairs"
  default = "gitopskey"
}

variable "kubeadm_ami_id" {
    type = string
    description = "ami id for our ubuntu"
    default = "ami-0c7217cdde317cfec"
}