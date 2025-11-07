# Bootstrap Configuration (DEPRECATED)

⚠️ **This directory is deprecated and no longer maintained.**

## Migration Path

This manual bootstrap approach has been replaced by the **automated scripts workflow**:

→ **Use `scripts/` directory instead** - Automated machine discovery and configuration

### Old Workflow (Deprecated)
```
bootstrap/
  - Manually configure machines.yaml
  - Manually generate cluster templates
  - Manually track UUIDs
```

### New Workflow (Recommended)
```
scripts/
  ✅ Automatic machine discovery from Terraform
  ✅ Automatic UUID matching by MAC address
  ✅ Dynamic machine config generation
  ✅ Automatic application to Omni
```

## How to Use the New Workflow

```bash
cd scripts/

# 1. Discover machines from Omni (matches Terraform VMs by MAC)
./discover-machines.sh

# 2. Generate machine configurations
./generate-machine-configs.sh

# 3. Apply to Omni
./apply-machine-configs.sh
```

See [scripts/README.md](../scripts/README.md) for detailed documentation.

## Why This Was Deprecated

The bootstrap approach required:
- ❌ Manual UUID tracking
- ❌ Manual IP/hostname assignment
- ❌ Manual machines.yaml editing
- ❌ No integration with Terraform

The new scripts workflow provides:
- ✅ Automatic Terraform → Omni integration
- ✅ MAC address-based matching
- ✅ Dynamic configuration generation
- ✅ Production-ready templates

## Files in This Directory

**Historical reference only** - Do not use for new deployments

- `cluster-template.yaml` - Old static cluster template
- `machines.yaml` - Old static machine definitions
- `generate-cluster-template.sh` - Old generation script
- `patches/` - Old patch files

---

**For current deployment guide**: See [root README.md](../README.md)
