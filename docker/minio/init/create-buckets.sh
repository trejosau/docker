#!/bin/sh
set -eu

required_variables="MINIO_ROOT_USER MINIO_ROOT_PASSWORD MINIO_APP_ACCESS_KEY MINIO_APP_SECRET_KEY MINIO_PRIVATE_BUCKET MINIO_BACKUPS_BUCKET"
for variable_name in $required_variables; do
  eval "variable_value=\${$variable_name:-}"
  if [ -z "$variable_value" ]; then
    echo "Required MinIO initialization variable is empty: $variable_name" >&2
    exit 1
  fi
done

alias_name="misvales-local"
endpoint="http://minio:9000"

until mc alias set "$alias_name" "$endpoint" "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null 2>&1; do
  echo "Waiting for MinIO..."
  sleep 2
done

for bucket_name in "$MINIO_PRIVATE_BUCKET" "$MINIO_BACKUPS_BUCKET"; do
  mc mb --ignore-existing "$alias_name/$bucket_name"
  mc version enable "$alias_name/$bucket_name"
  mc anonymous set none "$alias_name/$bucket_name"
  mc stat "$alias_name/$bucket_name" >/dev/null

  anonymous_status="$(mc anonymous get "$alias_name/$bucket_name" 2>&1 || true)"
  if ! printf '%s' "$anonymous_status" | grep -qi 'private'; then
    echo "Bucket $bucket_name did not report private anonymous access." >&2
    printf '%s\n' "$anonymous_status" >&2
    exit 1
  fi
done

policy_file="/tmp/misvales-app-policy.json"
cat > "$policy_file" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:GetBucketLocation", "s3:ListBucket", "s3:ListBucketMultipartUploads"],
      "Resource": [
        "arn:aws:s3:::$MINIO_PRIVATE_BUCKET",
        "arn:aws:s3:::$MINIO_BACKUPS_BUCKET"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:AbortMultipartUpload",
        "s3:DeleteObject",
        "s3:GetObject",
        "s3:ListMultipartUploadParts",
        "s3:PutObject"
      ],
      "Resource": [
        "arn:aws:s3:::$MINIO_PRIVATE_BUCKET/*",
        "arn:aws:s3:::$MINIO_BACKUPS_BUCKET/*"
      ]
    }
  ]
}
EOF

mc admin user add "$alias_name" "$MINIO_APP_ACCESS_KEY" "$MINIO_APP_SECRET_KEY" >/dev/null
# `policy create` also overwrites an existing policy, which keeps this rerunnable.
mc admin policy create "$alias_name" misvales-app-policy "$policy_file" >/dev/null
mc admin policy attach "$alias_name" misvales-app-policy --user "$MINIO_APP_ACCESS_KEY" >/dev/null
mc admin user info "$alias_name" "$MINIO_APP_ACCESS_KEY" >/dev/null

echo "MinIO private buckets and restricted application account are ready."
