# Skill: backup (see ./backup/SKILL.md). No extra deps: btrfs-progs/snapper are
# provided at the system level.
{ ... }:
{
  home.file.".claude/skills/backup" = {
    recursive = true;
    source = ./backup;
  };
}
