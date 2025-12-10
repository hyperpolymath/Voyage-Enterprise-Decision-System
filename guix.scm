;; Voyage-Enterprise-Decision-System - Guix Package Definition
;; Run: guix shell -D -f guix.scm

(use-modules (guix packages)
             (guix gexp)
             (guix git-download)
             (guix build-system gnu)
             ((guix licenses) #:prefix license:)
             (gnu packages base))

(define-public voyage_enterprise_decision_system
  (package
    (name "Voyage-Enterprise-Decision-System")
    (version "0.1.0")
    (source (local-file "." "Voyage-Enterprise-Decision-System-checkout"
                        #:recursive? #t
                        #:select? (git-predicate ".")))
    (build-system gnu-build-system)
    (synopsis "Guix channel/infrastructure")
    (description "Guix channel/infrastructure - part of the RSR ecosystem.")
    (home-page "https://github.com/hyperpolymath/Voyage-Enterprise-Decision-System")
    (license license:agpl3+)))

;; Return package for guix shell
voyage_enterprise_decision_system
