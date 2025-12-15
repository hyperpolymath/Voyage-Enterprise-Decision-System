;; SPDX-License-Identifier: AGPL-3.0-or-later
;; SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell
;; ECOSYSTEM.scm — voyage-enterprise-decision-system

(ecosystem
  (version "1.0.0")
  (name "voyage-enterprise-decision-system")
  (type "project")
  (purpose "*A multimodal transport optimization platform with formal verification*")

  (position-in-ecosystem
    "Part of hyperpolymath ecosystem. Follows RSR guidelines.")

  (related-projects
    (project (name "rhodium-standard-repositories")
             (url "https://github.com/hyperpolymath/rhodium-standard-repositories")
             (relationship "standard")))

  (what-this-is "*A multimodal transport optimization platform with formal verification*")
  (what-this-is-not "- NOT exempt from RSR compliance"))
