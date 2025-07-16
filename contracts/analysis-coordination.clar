;; Analysis Coordination Contract
;; Coordinates feedback analysis workflows and quality scoring

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u300))
(define-constant ERR-ANALYSIS-NOT-FOUND (err u301))
(define-constant ERR-INVALID-INPUT (err u302))
(define-constant ERR-ALREADY-ASSIGNED (err u303))
(define-constant ERR-INVALID-STATUS (err u304))

;; Analysis rewards
(define-constant ANALYSIS-REWARD u15)
(define-constant QUALITY-BONUS u10)

;; Data Variables
(define-data-var next-analysis-id uint u1)
(define-data-var total-analyses uint u0)
(define-data-var pending-analyses uint u0)

;; Data Maps
(define-map analysis-tasks
  { analysis-id: uint }
  {
    feedback-ids: (list 10 uint),
    assigned-analyst: (optional uint),
    category: (string-ascii 30),
    priority: (string-ascii 10),
    creation-time: uint,
    deadline: uint,
    status: (string-ascii 20),
    completion-time: (optional uint)
  }
)

(define-map analysis-results
  { analysis-id: uint }
  {
    analyst-id: uint,
    findings: (string-ascii 1000),
    recommendations: (string-ascii 1000),
    severity-score: uint,
    confidence-level: uint,
    quality-score: uint,
    submission-time: uint
  }
)

(define-map analyst-performance
  { analyst-id: uint }
  {
    total-analyses: uint,
    average-quality: uint,
    on-time-completion: uint,
    total-earnings: uint,
    last-activity: uint
  }
)

(define-map analysis-metrics
  { category: (string-ascii 30) }
  {
    total-analyses: uint,
    average-severity: uint,
    completion-rate: uint,
    average-quality: uint
  }
)

;; Public Functions

;; Create analysis task
(define-public (create-analysis-task (feedback-ids (list 10 uint)) (category (string-ascii 30)) (priority (string-ascii 10)) (deadline uint))
  (let
    (
      (analysis-id (var-get next-analysis-id))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (> (len feedback-ids) u0) ERR-INVALID-INPUT)
    (asserts! (> deadline block-height) ERR-INVALID-INPUT)

    (map-set analysis-tasks
      { analysis-id: analysis-id }
      {
        feedback-ids: feedback-ids,
        assigned-analyst: none,
        category: category,
        priority: priority,
        creation-time: block-height,
        deadline: deadline,
        status: "pending",
        completion-time: none
      }
    )

    (var-set next-analysis-id (+ analysis-id u1))
    (var-set total-analyses (+ (var-get total-analyses) u1))
    (var-set pending-analyses (+ (var-get pending-analyses) u1))

    (ok analysis-id)
  )
)

;; Assign analysis to analyst
(define-public (assign-analysis (analysis-id uint) (analyst-id uint))
  (let
    (
      (analysis (unwrap! (map-get? analysis-tasks { analysis-id: analysis-id }) ERR-ANALYSIS-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status analysis) "pending") ERR-INVALID-STATUS)
    (asserts! (is-none (get assigned-analyst analysis)) ERR-ALREADY-ASSIGNED)

    (map-set analysis-tasks
      { analysis-id: analysis-id }
      (merge analysis {
        assigned-analyst: (some analyst-id),
        status: "assigned"
      })
    )

    (ok true)
  )
)

;; Submit analysis results
(define-public (submit-analysis (analysis-id uint) (analyst-id uint) (findings (string-ascii 1000)) (recommendations (string-ascii 1000)) (severity-score uint) (confidence-level uint))
  (let
    (
      (analysis (unwrap! (map-get? analysis-tasks { analysis-id: analysis-id }) ERR-ANALYSIS-NOT-FOUND))
      (quality-score (calculate-quality-score severity-score confidence-level (get deadline analysis)))
    )
    (asserts! (is-eq (some analyst-id) (get assigned-analyst analysis)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status analysis) "assigned") ERR-INVALID-STATUS)
    (asserts! (<= severity-score u10) ERR-INVALID-INPUT)
    (asserts! (<= confidence-level u100) ERR-INVALID-INPUT)
    (asserts! (> (len findings) u0) ERR-INVALID-INPUT)

    (map-set analysis-results
      { analysis-id: analysis-id }
      {
        analyst-id: analyst-id,
        findings: findings,
        recommendations: recommendations,
        severity-score: severity-score,
        confidence-level: confidence-level,
        quality-score: quality-score,
        submission-time: block-height
      }
    )

    (map-set analysis-tasks
      { analysis-id: analysis-id }
      (merge analysis {
        status: "completed",
        completion-time: (some block-height)
      })
    )

    ;; Update analyst performance
    (update-analyst-performance analyst-id quality-score (get deadline analysis))

    ;; Update category metrics
    (update-analysis-metrics (get category analysis) severity-score quality-score)

    (var-set pending-analyses (- (var-get pending-analyses) u1))

    (ok quality-score)
  )
)

;; Update analysis status
(define-public (update-analysis-status (analysis-id uint) (new-status (string-ascii 20)))
  (let
    (
      (analysis (unwrap! (map-get? analysis-tasks { analysis-id: analysis-id }) ERR-ANALYSIS-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)

    (map-set analysis-tasks
      { analysis-id: analysis-id }
      (merge analysis { status: new-status })
    )

    (ok true)
  )
)

;; Private Functions

;; Calculate quality score based on various factors
(define-private (calculate-quality-score (severity uint) (confidence uint) (deadline uint))
  (let
    (
      (timeliness-bonus (if (<= block-height deadline) u20 u0))
      (confidence-factor (/ confidence u10))
      (severity-factor (if (>= severity u7) u15 u10))
    )
    (+ confidence-factor severity-factor timeliness-bonus)
  )
)

;; Update analyst performance metrics
(define-private (update-analyst-performance (analyst-id uint) (quality-score uint) (deadline uint))
  (let
    (
      (current-performance (default-to
        { total-analyses: u0, average-quality: u0, on-time-completion: u0, total-earnings: u0, last-activity: u0 }
        (map-get? analyst-performance { analyst-id: analyst-id })
      ))
      (new-total (+ (get total-analyses current-performance) u1))
      (new-avg-quality (/ (+ (* (get average-quality current-performance) (get total-analyses current-performance)) quality-score) new-total))
      (on-time (if (<= block-height deadline) u1 u0))
      (new-on-time (+ (get on-time-completion current-performance) on-time))
      (earnings (+ ANALYSIS-REWARD (if (>= quality-score u80) QUALITY-BONUS u0)))
    )
    (map-set analyst-performance
      { analyst-id: analyst-id }
      {
        total-analyses: new-total,
        average-quality: new-avg-quality,
        on-time-completion: new-on-time,
        total-earnings: (+ (get total-earnings current-performance) earnings),
        last-activity: block-height
      }
    )
  )
)

;; Update analysis metrics by category
(define-private (update-analysis-metrics (category (string-ascii 30)) (severity uint) (quality uint))
  (let
    (
      (current-metrics (default-to
        { total-analyses: u0, average-severity: u0, completion-rate: u0, average-quality: u0 }
        (map-get? analysis-metrics { category: category })
      ))
      (new-total (+ (get total-analyses current-metrics) u1))
      (new-avg-severity (/ (+ (* (get average-severity current-metrics) (get total-analyses current-metrics)) severity) new-total))
      (new-avg-quality (/ (+ (* (get average-quality current-metrics) (get total-analyses current-metrics)) quality) new-total))
    )
    (map-set analysis-metrics
      { category: category }
      {
        total-analyses: new-total,
        average-severity: new-avg-severity,
        completion-rate: u100,
        average-quality: new-avg-quality
      }
    )
  )
)

;; Read-only Functions

;; Get analysis task details
(define-read-only (get-analysis-task (analysis-id uint))
  (map-get? analysis-tasks { analysis-id: analysis-id })
)

;; Get analysis results
(define-read-only (get-analysis-results (analysis-id uint))
  (map-get? analysis-results { analysis-id: analysis-id })
)

;; Get analyst performance
(define-read-only (get-analyst-performance (analyst-id uint))
  (map-get? analyst-performance { analyst-id: analyst-id })
)

;; Get analysis metrics by category
(define-read-only (get-analysis-metrics (category (string-ascii 30)))
  (map-get? analysis-metrics { category: category })
)

;; Get total analyses count
(define-read-only (get-total-analyses)
  (var-get total-analyses)
)

;; Get pending analyses count
(define-read-only (get-pending-analyses)
  (var-get pending-analyses)
)
