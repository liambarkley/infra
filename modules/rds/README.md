# modules/rds

A small Postgres instance for `platform/apps/demo-spring-app` (phase 3). Not multi-AZ, no
automated backups, no final snapshot on destroy - deliberately: this is a disposable demo
database, destroyed along with the rest of `envs/dev` between sessions
(`docs/PLAN.md`'s cost-control section), so none of that resilience machinery has anything to
protect. The project's real backup/DR story is Velero (phase 5), for the cluster's own state.

## No password anywhere in this repo

`aws_db_instance.this` sets `manage_master_user_password = true` and no `password` attribute -
RDS generates the master password itself and stores it in AWS Secrets Manager, so it never
exists in Terraform config, state diffs, or committed files. `master_user_secret_arn` is the
one thing the demo app needs: it reads the actual password from Secrets Manager at runtime via
its own IAM role (Pod Identity, same pattern as Karpenter and the Load Balancer Controller -
see `infra/modules/eks`), not from anything written here.

## Network access

One security group, one rule: Postgres (5432) from the EKS cluster security group only
(`modules/eks`'s `cluster_security_group_id` output) - every pod in the cluster can reach this
regardless of which node group it's scheduled on (the system node group and Karpenter-launched
nodes both get this same security group attached automatically), and nothing outside the VPC
can.

## Inputs / outputs

See `variables.tf` and `outputs.tf`. `envs/dev` wires `modules/network`'s private subnets and
`modules/eks`'s cluster security group in.
