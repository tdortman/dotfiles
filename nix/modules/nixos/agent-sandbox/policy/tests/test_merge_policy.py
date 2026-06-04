#!/usr/bin/env python3
"""Tests for project policy path resolution."""

from __future__ import annotations

import json
import os
import shutil
import tempfile
import unittest
from pathlib import Path

from support import load_module

merge_policy = load_module("merge_policy", "daemon/merge_policy.py")


class ProjectPolicyPathTests(unittest.TestCase):
    def test_prefers_project_root_over_ephemeral_cwd(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp) / "dotfiles"
            repo.mkdir()
            policy_dir = repo / ".agent-sandbox"
            policy_dir.mkdir()
            policy_file = policy_dir / "policy.json"
            policy_file.write_text(
                '{"network":{"allow":[],"deny":[]},"sudo":{"allow":[],"deny":[]}}\n',
                encoding="utf-8",
            )

            ephemeral = Path(tmp) / "omp-python-runner"
            ephemeral.mkdir()

            resolved = merge_policy.resolve_project_policy_path(
                cwd=ephemeral,
                project_root=repo,
            )
            self.assertEqual(resolved, policy_file)

    def test_ephemeral_cwd_without_project_root_raises(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            ephemeral = Path(tmp) / "omp-python-runner"
            ephemeral.mkdir()
            with self.assertRaises(ValueError):
                merge_policy.resolve_project_policy_path(cwd=ephemeral)

    def test_rejects_root_cwd(self) -> None:
        with self.assertRaises(ValueError):
            merge_policy.resolve_project_policy_path(cwd="/")

    def test_rejects_root_project_root(self) -> None:
        with self.assertRaises(ValueError):
            merge_policy.resolve_project_policy_path(project_root="/")

    def test_discovers_existing_policy_from_cwd(self) -> None:
        base = Path(__file__).resolve().parent / ".test_proj_discovery"
        shutil.rmtree(base, ignore_errors=True)
        base.mkdir()
        try:
            repo = base / "proj"
            repo.mkdir()
            policy_file = repo / ".agent-sandbox" / "policy.json"
            policy_file.parent.mkdir(parents=True)
            policy_file.write_text(
                '{"network":{"allow":[],"deny":[]},"sudo":{"allow":[],"deny":[]}}\n',
                encoding="utf-8",
            )

            resolved = merge_policy.resolve_project_policy_path(cwd=repo / "src")
            self.assertEqual(resolved, policy_file)
        finally:
            shutil.rmtree(base, ignore_errors=True)


class MergeLayersTests(unittest.TestCase):
    def test_deny_removes_allow_from_earlier_layer(self) -> None:
        low = {
            "network": {
                "allow": [{"host": "example.com", "port": 443}],
                "deny": [],
            },
            "sudo": {"allow": [], "deny": []},
        }
        high = {
            "network": {
                "allow": [],
                "deny": [{"host": "example.com", "port": 443}],
            },
            "sudo": {"allow": [], "deny": []},
        }
        merged = merge_policy.merge_layers(low, high)
        self.assertEqual(merged["network"]["allow"], [])
        self.assertEqual(len(merged["network"]["deny"]), 1)

    def test_allow_removes_deny_from_earlier_layer(self) -> None:
        low = {
            "network": {
                "allow": [],
                "deny": [{"host": "example.com", "port": 443}],
            },
            "sudo": {"allow": [], "deny": []},
        }
        high = {
            "network": {
                "allow": [{"host": "example.com", "port": 443}],
                "deny": [],
            },
            "sudo": {"allow": [], "deny": []},
        }
        merged = merge_policy.merge_layers(low, high)
        self.assertEqual(len(merged["network"]["allow"]), 1)
        self.assertEqual(merged["network"]["deny"], [])

    def test_sudo_deny_beats_allow(self) -> None:
        low = {
            "network": {"allow": [], "deny": []},
            "sudo": {"allow": [{"argv": ["whoami"]}], "deny": []},
        }
        high = {
            "network": {"allow": [], "deny": []},
            "sudo": {"allow": [], "deny": [{"argv": ["whoami"]}]},
        }
        merged = merge_policy.merge_layers(low, high)
        self.assertEqual(merged["sudo"]["allow"], [])
        self.assertEqual(len(merged["sudo"]["deny"]), 1)

    def test_sudo_argv_prefix_match(self) -> None:
        rule = {"argv": ["systemctl", "restart"]}
        self.assertTrue(
            merge_policy.sudo_argv_matches(rule, ["systemctl", "restart", "nginx"])
        )
        self.assertFalse(merge_policy.sudo_argv_matches(rule, ["systemctl", "stop"]))

    def test_infer_home_from_project_root(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp) / "home" / "tim"
            repo = home / "dotfiles"
            repo.mkdir(parents=True)
            self.assertEqual(
                merge_policy.infer_home_from_paths(str(repo)),
                str(home),
            )
            self.assertIsNone(merge_policy.infer_home_from_paths("/var/tmp/runner"))

    def test_project_policy_paths_discovers_under_home(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp) / "home" / "tim"
            repo = home / "dotfiles"
            policy_dir = repo / ".agent-sandbox"
            policy_dir.mkdir(parents=True)
            policy_file = policy_dir / "policy.json"
            policy_file.write_text(
                '{"network":{"allow":[],"deny":[{"host":"chatgpt.com","port":443}]},"sudo":{"allow":[],"deny":[]}}\n',
                encoding="utf-8",
            )
            paths = merge_policy.project_policy_paths(home=str(home))
            self.assertEqual(paths, [policy_file.resolve()])

    def test_project_deny_beats_global_allow(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp) / "home" / "tim"
            repo = home / "dotfiles"
            policy_dir = repo / ".agent-sandbox"
            policy_dir.mkdir(parents=True)
            (policy_dir / "policy.json").write_text(
                '{"network":{"allow":[],"deny":[{"host":"chatgpt.com","port":443}]},"sudo":{"allow":[],"deny":[]}}\n',
                encoding="utf-8",
            )
            (home / ".config" / "agent-sandbox").mkdir(parents=True)
            (home / ".config" / "agent-sandbox" / "policy.json").write_text(
                '{"network":{"allow":[{"host":"chatgpt.com","port":443}],"deny":[]},"sudo":{"allow":[],"deny":[]}}\n',
                encoding="utf-8",
            )
            layers = [
                {
                    "network": {
                        "allow": [{"host": "chatgpt.com", "port": 443}],
                        "deny": [],
                    },
                    "sudo": {"allow": [], "deny": []},
                },
                merge_policy.load_policy(
                    home / ".config" / "agent-sandbox" / "policy.json"
                ),
            ]
            for path in merge_policy.project_policy_paths(home=str(home)):
                layers.append(merge_policy.load_policy(path))
            merged = merge_policy.merge_layers(*layers)
            self.assertEqual(merged["network"]["deny"][0]["host"], "chatgpt.com")
            self.assertEqual(merged["network"]["allow"], [])

    def test_atomic_write_policy_preserves_symlink(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp) / "dotfiles"
            repo.mkdir()
            real = repo / "home" / "dot_config" / "agent-sandbox"
            real.mkdir(parents=True)
            real_policy = real / "policy.json"
            real_policy.write_text(
                '{"network":{"allow":[],"deny":[]},"sudo":{"allow":[],"deny":[]}}\n',
                encoding="utf-8",
            )
            link = Path(tmp) / "policy.json"
            link.symlink_to(real_policy)
            merge_policy.atomic_write_policy(
                link,
                {
                    "network": {
                        "allow": [{"host": "example.com", "port": 443}],
                        "deny": [],
                    },
                    "sudo": {"allow": [], "deny": []},
                },
            )
            self.assertTrue(link.is_symlink())
            loaded = json.loads(real_policy.read_text(encoding="utf-8"))
            self.assertEqual(loaded["network"]["allow"][0]["host"], "example.com")

    def test_atomic_write_policy_chowns_to_owner(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp) / "project"
            repo.mkdir()
            policy_path = repo / ".agent-sandbox" / "policy.json"
            merge_policy.atomic_write_policy(
                policy_path,
                {
                    "network": {"allow": [], "deny": []},
                    "sudo": {"allow": [], "deny": []},
                },
                owner_uid=os.getuid(),
            )
            self.assertEqual(policy_path.stat().st_uid, os.getuid())
            self.assertEqual(policy_path.parent.stat().st_uid, os.getuid())


if __name__ == "__main__":
    unittest.main()
