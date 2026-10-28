# modules/network

VPC with public and private subnets across the given availability zones, one NAT gateway (not
one per AZ — cost control, see `docs/PLAN.md`), and the route tables wiring it together.

Every resource is tagged `project = "build-cache"` plus whatever `tags` the caller passes in.

## Inputs / outputs

See `variables.tf` and `outputs.tf`. Nothing here talks to the EKS module directly — `envs/dev`
wires the subnet IDs into whichever module needs them.
