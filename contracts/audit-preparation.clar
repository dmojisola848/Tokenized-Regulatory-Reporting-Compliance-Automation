;; Audit Preparation Contract
;; Prepares compliance audits and manages audit trails

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u500))
(define-constant ERR-AUDIT-NOT-FOUND (err u501))
(define-constant ERR-INVALID-DATE-RANGE (err u502))
(define-constant ERR-EVIDENCE-NOT-FOUND (err u503))
(define-constant ERR-AUDIT-ALREADY-COMPLETED (err u504))

;; Data Variables
(define-data-var next-audit-id uint u1)
(define-data-var next-evidence-id uint u1)
(define-data-var total-audits uint u0)
(define-data-var active-audits uint u0)

;; Data Maps
(define-map audits
  { audit-id: uint }
  {
    title: (string-ascii 200),
    audit-type: (string-ascii 50),
    coordinator-id: uint,
    auditor-id: uint,
    start-date: uint,
    end-date: uint,
    status: (string-ascii 20),
    scope: (string-ascii 500),
    created-at: uint,
    completed-at: uint,
    compliance-rating: uint
  }
)

(define-map audit-evidence
  { evidence-id: uint }
  {
    audit-id: uint,
    evidence-type: (string-ascii 50),
    description: (string-ascii 500),
    data-hash: (buff 32),
    source-contract: (string-ascii 100),
    collected-at: uint,
    verified: bool,
    importance-level: (string-ascii 10)
  }
)

(define-map audit-trails
  { audit-id: uint }
  {
    transaction-hashes: (list 100 (buff 32)),
    validation-records: (list 50 uint),
    submission-records: (list 50 uint),
    coordinator-activities: (list 100 uint),
    evidence-count: uint,
    trail-completeness: uint
  }
)

(define-map audit-findings
  { audit-id: uint }
  {
    total-findings: uint,
    critical-findings: uint,
    major-findings: uint,
    minor-findings: uint,
    recommendations: (string-ascii 1000),
    corrective-actions: (string-ascii 1000),
    follow-up-required: bool
  }
)

;; Public Functions

;; Create a new audit
(define-public (create-audit (title (string-ascii 200)) (audit-type (string-ascii 50)) (coordinator-id uint) (auditor-id uint) (start-date uint) (end-date uint) (scope (string-ascii 500)))
  (let
    (
      (audit-id (var-get next-audit-id))
      (current-block block-height)
    )
    (asserts! (< start-date end-date) ERR-INVALID-DATE-RANGE)
    (asserts! (>= start-date current-block) ERR-INVALID-DATE-RANGE)

    ;; Create audit record
    (map-set audits
      { audit-id: audit-id }
      {
        title: title,
        audit-type: audit-type,
        coordinator-id: coordinator-id,
        auditor-id: auditor-id,
        start-date: start-date,
        end-date: end-date,
        status: "scheduled",
        scope: scope,
        created-at: current-block,
        completed-at: u0,
        compliance-rating: u0
      }
    )

    ;; Initialize audit trail
    (map-set audit-trails
      { audit-id: audit-id }
      {
        transaction-hashes: (list),
        validation-records: (list),
        submission-records: (list),
        coordinator-activities: (list),
        evidence-count: u0,
        trail-completeness: u0
      }
    )

    ;; Update counters
    (var-set next-audit-id (+ audit-id u1))
    (var-set total-audits (+ (var-get total-audits) u1))
    (var-set active-audits (+ (var-get active-audits) u1))

    (ok audit-id)
  )
)

;; Collect audit evidence
(define-public (collect-evidence (audit-id uint) (evidence-type (string-ascii 50)) (description (string-ascii 500)) (data-hash (buff 32)) (source-contract (string-ascii 100)) (importance-level (string-ascii 10)))
  (let
    (
      (evidence-id (var-get next-evidence-id))
      (audit (unwrap! (map-get? audits { audit-id: audit-id }) ERR-AUDIT-NOT-FOUND))
      (trail (unwrap! (map-get? audit-trails { audit-id: audit-id }) ERR-AUDIT-NOT-FOUND))
      (current-block block-height)
    )
    (asserts! (not (is-eq (get status audit) "completed")) ERR-AUDIT-ALREADY-COMPLETED)

    ;; Create evidence record
    (map-set audit-evidence
      { evidence-id: evidence-id }
      {
        audit-id: audit-id,
        evidence-type: evidence-type,
        description: description,
        data-hash: data-hash,
        source-contract: source-contract,
        collected-at: current-block,
        verified: false,
        importance-level: importance-level
      }
    )

    ;; Update audit trail
    (map-set audit-trails
      { audit-id: audit-id }
      (merge trail {
        evidence-count: (+ (get evidence-count trail) u1)
      })
    )

    (var-set next-evidence-id (+ evidence-id u1))
    (ok evidence-id)
  )
)

;; Verify evidence
(define-public (verify-evidence (evidence-id uint) (verified bool))
  (let
    (
      (evidence (unwrap! (map-get? audit-evidence { evidence-id: evidence-id }) ERR-EVIDENCE-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)

    (map-set audit-evidence
      { evidence-id: evidence-id }
      (merge evidence { verified: verified })
    )

    (ok true)
  )
)

;; Generate audit trail
(define-public (generate-audit-trail (audit-id uint) (validation-records (list 50 uint)) (submission-records (list 50 uint)) (coordinator-activities (list 100 uint)))
  (let
    (
      (audit (unwrap! (map-get? audits { audit-id: audit-id }) ERR-AUDIT-NOT-FOUND))
      (trail (unwrap! (map-get? audit-trails { audit-id: audit-id }) ERR-AUDIT-NOT-FOUND))
    )
    (asserts! (is-eq (get status audit) "in-progress") ERR-NOT-AUTHORIZED)

    ;; Update audit trail with collected data
    (map-set audit-trails
      { audit-id: audit-id }
      (merge trail {
        validation-records: validation-records,
        submission-records: submission-records,
        coordinator-activities: coordinator-activities,
        trail-completeness: (calculate-trail-completeness validation-records submission-records coordinator-activities)
      })
    )

    (ok true)
  )
)

;; Complete audit
(define-public (complete-audit (audit-id uint) (compliance-rating uint) (total-findings uint) (critical-findings uint) (major-findings uint) (minor-findings uint) (recommendations (string-ascii 1000)) (corrective-actions (string-ascii 1000)))
  (let
    (
      (audit (unwrap! (map-get? audits { audit-id: audit-id }) ERR-AUDIT-NOT-FOUND))
      (current-block block-height)
    )
    (asserts! (is-eq (get status audit) "in-progress") ERR-AUDIT-ALREADY-COMPLETED)
    (asserts! (<= compliance-rating u100) ERR-NOT-AUTHORIZED)

    ;; Update audit record
    (map-set audits
      { audit-id: audit-id }
      (merge audit {
        status: "completed",
        completed-at: current-block,
        compliance-rating: compliance-rating
      })
    )

    ;; Record audit findings
    (map-set audit-findings
      { audit-id: audit-id }
      {
        total-findings: total-findings,
        critical-findings: critical-findings,
        major-findings: major-findings,
        minor-findings: minor-findings,
        recommendations: recommendations,
        corrective-actions: corrective-actions,
        follow-up-required: (> critical-findings u0)
      }
    )

    ;; Update active audits counter
    (var-set active-audits (- (var-get active-audits) u1))

    (ok true)
  )
)

;; Update audit status
(define-public (update-audit-status (audit-id uint) (new-status (string-ascii 20)))
  (let
    (
      (audit (unwrap! (map-get? audits { audit-id: audit-id }) ERR-AUDIT-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)

    (map-set audits
      { audit-id: audit-id }
      (merge audit { status: new-status })
    )

    (ok true)
  )
)

;; Read-only Functions

;; Get audit information
(define-read-only (get-audit (audit-id uint))
  (map-get? audits { audit-id: audit-id })
)

;; Get audit evidence
(define-read-only (get-evidence (evidence-id uint))
  (map-get? audit-evidence { evidence-id: evidence-id })
)

;; Get audit trail
(define-read-only (get-audit-trail (audit-id uint))
  (map-get? audit-trails { audit-id: audit-id })
)

;; Get audit findings
(define-read-only (get-audit-findings (audit-id uint))
  (map-get? audit-findings { audit-id: audit-id })
)

;; Get total audits
(define-read-only (get-total-audits)
  (var-get total-audits)
)

;; Get active audits count
(define-read-only (get-active-audits)
  (var-get active-audits)
)

;; Check audit completeness
(define-read-only (is-audit-complete (audit-id uint))
  (match (map-get? audits { audit-id: audit-id })
    audit (is-eq (get status audit) "completed")
    false
  )
)

;; Get evidence by audit
(define-read-only (get-evidence-by-audit (audit-id uint))
  (get-evidence-by-audit-helper audit-id)
)

;; Private Functions

;; Helper function for getting evidence by audit
(define-private (get-evidence-by-audit-helper (target-audit-id uint))
  (let
    (
      (all-evidence (get-all-evidence-ids))
    )
    (fold check-evidence-audit-helper all-evidence { audit-id: target-audit-id, results: (list) })
  )
)

;; Helper function to check evidence audit
(define-private (check-evidence-audit-helper
  (evidence-id uint)
  (state { audit-id: uint, results: (list 100 uint) })
)
  (if (check-evidence-audit evidence-id (get audit-id state))
    {
      audit-id: (get audit-id state),
      results: (unwrap-panic (as-max-len? (append (get results state) evidence-id) u100))
    }
    state
  )
)

;; Calculate trail completeness percentage
(define-private (calculate-trail-completeness (validations (list 50 uint)) (submissions (list 50 uint)) (activities (list 100 uint)))
  (let
    (
      (validation-score (if (> (len validations) u0) u30 u0))
      (submission-score (if (> (len submissions) u0) u30 u0))
      (activity-score (if (> (len activities) u0) u40 u0))
    )
    (+ validation-score (+ submission-score activity-score))
  )
)

;; Check if evidence belongs to audit (helper function)
(define-private (check-evidence-audit (evidence-id uint) (target-audit-id uint))
  (match (map-get? audit-evidence { evidence-id: evidence-id })
    evidence (is-eq (get audit-id evidence) target-audit-id)
    false
  )
)

;; Get all evidence IDs (simplified for demonstration)
(define-private (get-all-evidence-ids)
  (list u1 u2 u3 u4 u5) ;; In practice, this would be dynamically generated
)
