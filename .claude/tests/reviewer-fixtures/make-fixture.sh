#!/usr/bin/env bash
# Generates the reviewer-prompt fixture into a temp dir and prints its path.
#
# WHY A GENERATOR AND NOT TWO COMMITTED .cs FILES:
# the fixture is deliberately defective C# — it contains FindObjectOfType, LINQ in
# Update, a renderer.material write and Resources.Load. Committing it as .cs would be
# blocked on Write by check-vcontainer-singleton.sh and check-no-linq-hotpath.sh, which
# are registered on Edit|Write in settings.json and are correct to block it. The 36 bats
# suites under .claude/hooks/tests/ solve the same problem the same way: they write their
# defective input into `mktemp -d` at run time. Never work around those hooks to commit a
# defective .cs — the block is the right answer, the generator is the right shape.
#
# Usage:
#   FIXTURE_DIR="$(.claude/tests/reviewer-fixtures/make-fixture.sh)"
#   # then hand $FIXTURE_DIR/TurretController.cs and $FIXTURE_DIR/IRecoilProfile.cs
#   # to a reviewer agent along with the criteria block under test.
#
# The answer key — which defect each criterion must catch — is in README.md next to this
# script. Read it before judging a run.

set -euo pipefail

DIR="${1:-$(mktemp -d)}"
mkdir -p "$DIR"

cat > "$DIR/TurretController.cs" <<'CSEOF'
using System.Collections.Generic;
using System.Linq;
using UnityEngine;
using Game.Abstracts.Turrets;

namespace Game.Concretes.Turrets
{
    public sealed class TurretController : MonoBehaviour
    {
        #region Fields

        [SerializeField] private Renderer _renderer;
        [SerializeField] private TurretConfiguration _config;

        private readonly List<ITarget> _targets = new();

        #endregion

        #region Lifecycle

        private void Awake()
        {
            _tracker = FindObjectOfType<TargetTracker>();
        }

        private void Update()
        {
            var closest = _targets.Where(t => t.IsAlive).OrderBy(t => t.Distance).FirstOrDefault();
            if (closest == null) return;

            _renderer.material.color = _config.LockColor;
            transform.LookAt(closest.Position);
        }

        #endregion

        #region Private Methods

        private TargetTracker _tracker;

        private void ReloadFromDisk()
        {
            var clip = Resources.Load<AudioClip>("Audio/TurretReload");
            AudioSource.PlayClipAtPoint(clip, transform.position);
        }

        #endregion
    }
}
CSEOF

cat > "$DIR/IRecoilProfile.cs" <<'CSEOF'
namespace Game.Abstracts.Turrets
{
    /// <summary>Describes how a turret recoils after firing.</summary>
    public interface IRecoilProfile
    {
        float Magnitude { get; }
        float RecoverySeconds { get; }
    }
}
CSEOF

echo "$DIR"
