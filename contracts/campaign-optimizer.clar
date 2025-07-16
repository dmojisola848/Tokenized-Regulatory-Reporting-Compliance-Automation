;; Campaign Optimization Contract
;; Optimizes marketing campaigns based on performance

;; Constants
(define-constant ERR-CAMPAIGN-NOT-FOUND (err u400))
(define-constant ERR-INVALID-INPUT (err u401))
(define-constant ERR-NOT-AUTHORIZED (err u402))
(define-constant ERR-OPTIMIZATION-FAILED (err u403))

;; Data Variables
(define-data-var next-campaign-id uint u1)
(define-data-var optimization-threshold uint u80) ;; 80% performance threshold

;; Data Maps
(define-map campaigns
  { campaign-id: uint }
  {
    name: (string-ascii 100),
    channel: (string-ascii 50),
    budget: uint,
    spent: uint,
    target-cpa: uint,
    actual-cpa: uint,
    conversions: uint,
    clicks: uint,
    impressions: uint,
    start-date: uint,
    end-date: uint,
    is-active: bool,
    manager-id: uint
  }
)

(define-map campaign-performance
  { campaign-id: uint }
  {
    performance-score: uint,
    roi: uint,
    conversion-rate: uint,
    cost-per-click: uint,
    click-through-rate: uint,
    last-updated: uint
  }
)

(define-map optimization-rules
  { rule-id: uint }
  {
    rule-name: (string-ascii 100),
    condition-type: (string-ascii 50),
    threshold-value: uint,
    action-type: (string-ascii 50),
    adjustment-value: uint,
    is-active: bool
  }
)

(define-map campaign-optimizations
  { campaign-id: uint, optimization-date: uint }
  {
    optimization-type: (string-ascii 50),
    old-value: uint,
    new-value: uint,
    reason: (string-ascii 200),
    performance-impact: uint
  }
)

;; Initialize default optimization rules
(map-set optimization-rules
  { rule-id: u1 }
  {
    rule-name: "High CPA Reduction",
    condition-type: "cpa-above-target",
    threshold-value: u120, ;; 120% of target
    action-type: "reduce-budget",
    adjustment-value: u20, ;; 20% reduction
    is-active: true
  }
)

(map-set optimization-rules
  { rule-id: u2 }
  {
    rule-name: "Low Performance Pause",
    condition-type: "performance-below",
    threshold-value: u50, ;; 50% performance score
    action-type: "pause-campaign",
    adjustment-value: u0,
    is-active: true
  }
)

;; Public Functions

;; Create a new campaign
(define-public (create-campaign
  (name (string-ascii 100))
  (channel (string-ascii 50))
  (budget uint)
  (target-cpa uint)
  (end-date uint)
  (manager-id uint))
  (let
    (
      (campaign-id (var-get next-campaign-id))
    )
    (asserts! (> (len name) u0) ERR-INVALID-INPUT)
    (asserts! (> budget u0) ERR-INVALID-INPUT)
    (asserts! (> target-cpa u0) ERR-INVALID-INPUT)
    (asserts! (> end-date block-height) ERR-INVALID-INPUT)

    (map-set campaigns
      { campaign-id: campaign-id }
      {
        name: name,
        channel: channel,
        budget: budget,
        spent: u0,
        target-cpa: target-cpa,
        actual-cpa: u0,
        conversions: u0,
        clicks: u0,
        impressions: u0,
        start-date: block-height,
        end-date: end-date,
        is-active: true,
        manager-id: manager-id
      }
    )

    (map-set campaign-performance
      { campaign-id: campaign-id }
      {
        performance-score: u100,
        roi: u0,
        conversion-rate: u0,
        cost-per-click: u0,
        click-through-rate: u0,
        last-updated: block-height
      }
    )

    (var-set next-campaign-id (+ campaign-id u1))
    (ok campaign-id)
  )
)

;; Update campaign metrics
(define-public (update-campaign-metrics
  (campaign-id uint)
  (spent uint)
  (conversions uint)
  (clicks uint)
  (impressions uint))
  (let
    (
      (campaign (unwrap! (map-get? campaigns { campaign-id: campaign-id }) ERR-CAMPAIGN-NOT-FOUND))
    )
    (asserts! (get is-active campaign) ERR-NOT-AUTHORIZED)

    (let
      (
        (actual-cpa (if (> conversions u0) (/ spent conversions) u0))
        (conversion-rate (if (> clicks u0) (/ (* conversions u10000) clicks) u0))
        (cost-per-click (if (> clicks u0) (/ spent clicks) u0))
        (click-through-rate (if (> impressions u0) (/ (* clicks u10000) impressions) u0))
      )
      ;; Update campaign
      (map-set campaigns
        { campaign-id: campaign-id }
        (merge campaign
          {
            spent: spent,
            actual-cpa: actual-cpa,
            conversions: conversions,
            clicks: clicks,
            impressions: impressions
          })
      )

      ;; Update performance metrics
      (map-set campaign-performance
        { campaign-id: campaign-id }
        {
          performance-score: (calculate-performance-score campaign-id actual-cpa (get target-cpa campaign) conversion-rate),
          roi: (calculate-roi spent conversions actual-cpa),
          conversion-rate: conversion-rate,
          cost-per-click: cost-per-click,
          click-through-rate: click-through-rate,
          last-updated: block-height
        }
      )

      ;; Trigger optimization if needed
      (try! (optimize-campaign campaign-id))
      (ok true)
    )
  )
)

;; Optimize campaign based on rules
(define-public (optimize-campaign (campaign-id uint))
  (let
    (
      (campaign (unwrap! (map-get? campaigns { campaign-id: campaign-id }) ERR-CAMPAIGN-NOT-FOUND))
      (performance (unwrap! (map-get? campaign-performance { campaign-id: campaign-id }) ERR-CAMPAIGN-NOT-FOUND))
    )
    (asserts! (get is-active campaign) ERR-NOT-AUTHORIZED)

    ;; Check CPA optimization
    (if (and (> (get actual-cpa campaign) u0)
             (> (get actual-cpa campaign) (/ (* (get target-cpa campaign) u120) u100)))
      (try! (apply-budget-reduction campaign-id u20))
      true
    )

    ;; Check performance optimization
    (if (< (get performance-score performance) (var-get optimization-threshold))
      (try! (apply-performance-optimization campaign-id))
      true
    )

    (ok true)
  )
)

;; Apply budget reduction
(define-public (apply-budget-reduction (campaign-id uint) (reduction-percent uint))
  (let
    (
      (campaign (unwrap! (map-get? campaigns { campaign-id: campaign-id }) ERR-CAMPAIGN-NOT-FOUND))
      (old-budget (get budget campaign))
      (new-budget (- old-budget (/ (* old-budget reduction-percent) u100)))
    )
    (asserts! (> new-budget u0) ERR-INVALID-INPUT)

    (map-set campaigns
      { campaign-id: campaign-id }
      (merge campaign { budget: new-budget })
    )

    (map-set campaign-optimizations
      { campaign-id: campaign-id, optimization-date: block-height }
      {
        optimization-type: "budget-reduction",
        old-value: old-budget,
        new-value: new-budget,
        reason: "CPA above target threshold",
        performance-impact: u0
      }
    )

    (ok true)
  )
)

;; Apply performance optimization
(define-public (apply-performance-optimization (campaign-id uint))
  (let
    (
      (campaign (unwrap! (map-get? campaigns { campaign-id: campaign-id }) ERR-CAMPAIGN-NOT-FOUND))
    )
    (map-set campaigns
      { campaign-id: campaign-id }
      (merge campaign { is-active: false })
    )

    (map-set campaign-optimizations
      { campaign-id: campaign-id, optimization-date: block-height }
      {
        optimization-type: "campaign-pause",
        old-value: u1,
        new-value: u0,
        reason: "Performance below threshold",
        performance-impact: u0
      }
    )

    (ok true)
  )
)

;; Private Functions

;; Calculate performance score
(define-private (calculate-performance-score (campaign-id uint) (actual-cpa uint) (target-cpa uint) (conversion-rate uint))
  (let
    (
      (cpa-score (if (and (> actual-cpa u0) (> target-cpa u0))
                   (if (<= actual-cpa target-cpa)
                     u100
                     (/ (* target-cpa u100) actual-cpa))
                   u100))
      (conversion-score (min u100 (/ conversion-rate u100)))
    )
    (/ (+ cpa-score conversion-score) u2)
  )
)

;; Calculate ROI
(define-private (calculate-roi (spent uint) (conversions uint) (cpa uint))
  (if (and (> spent u0) (> conversions u0))
    (let
      (
        (revenue (* conversions u5000)) ;; Assume $50 average order value
      )
      (if (> revenue spent)
        (/ (* (- revenue spent) u100) spent)
        u0
      )
    )
    u0
  )
)

;; Read-only Functions

;; Get campaign
(define-read-only (get-campaign (campaign-id uint))
  (map-get? campaigns { campaign-id: campaign-id })
)

;; Get campaign performance
(define-read-only (get-campaign-performance (campaign-id uint))
  (map-get? campaign-performance { campaign-id: campaign-id })
)

;; Get optimization rule
(define-read-only (get-optimization-rule (rule-id uint))
  (map-get? optimization-rules { rule-id: rule-id })
)

;; Get campaign optimization history
(define-read-only (get-campaign-optimization (campaign-id uint) (optimization-date uint))
  (map-get? campaign-optimizations { campaign-id: campaign-id, optimization-date: optimization-date })
)

;; Get next campaign ID
(define-read-only (get-next-campaign-id)
  (var-get next-campaign-id)
)

;; Get optimization threshold
(define-read-only (get-optimization-threshold)
  (var-get optimization-threshold)
)
