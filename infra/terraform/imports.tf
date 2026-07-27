# Adopt the two buckets that ALREADY EXIST (full of data) into state, instead of
# letting Terraform try to create them (which would error on a name clash and,
# worse, risk a destroy/recreate of live data). `terraform plan` with these
# blocks shows "will import" not "will create"; verify that, then `apply`.
#
# skylab-stalwart-pg has NO import block on purpose — it doesn't exist yet, so
# Terraform creates it normally.
#
# After the first successful apply these blocks are inert no-ops; leave them
# (harmless, self-documenting) or delete them.
#
# R2 bucket import id is "<account_id>/<bucket_name>".
import {
  to = cloudflare_r2_bucket.loki
  id = "2620dc6ee3d578b27347d8e5efd95f32/skylab-loki"
}

import {
  to = cloudflare_r2_bucket.thanos
  id = "2620dc6ee3d578b27347d8e5efd95f32/skylab-thanos"
}
