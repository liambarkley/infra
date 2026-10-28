package main

# Every resource this project creates must carry project = "build-cache" (CLAUDE.md hard rule).
# Resource types that don't support tags at all (data sources, IAM policy documents, etc.) are
# exempt rather than special-cased by name, since the list of untaggable types is long and grows.

untaggable_types := {
	"random_id",
	"tls_certificate",
	"aws_iam_policy_document",
}

taggable_resource_changes[rc] {
	rc := input.resource_changes[_]
	rc.change.actions[_] != "delete"
	not untaggable_types[rc.type]
}

deny[msg] {
	rc := taggable_resource_changes[_]
	tags := object.get(rc.change.after, "tags_all", object.get(rc.change.after, "tags", {}))
	tags.project != "build-cache"
	msg := sprintf("%s.%s is missing tag project=build-cache", [rc.type, rc.name])
}
