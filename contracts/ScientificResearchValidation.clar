;; ScientificResearchValidation
;; Research validation and peer review system on Stacks

;; Constants
(define-constant ERR-NOT-AUTHORIZED (err u401))
(define-constant ERR-NOT-FOUND (err u404))
(define-constant ERR-INVALID-STATUS (err u400))
(define-constant CONTRACT-OWNER tx-sender)

;; Constants for validation
(define-constant ERR-INVALID-IPFS-HASH (err u403))
(define-constant ERR-INVALID-METHODOLOGY (err u405))
(define-constant ERR-INVALID-REPLICATIONS (err u406))
(define-constant ERR-INVALID-CREDENTIALS (err u407))
(define-constant ERR-INVALID-VERDICT (err u408))
(define-constant MAX-REPLICATIONS u100)

;; Data variables
(define-data-var next-submission-id uint u1)
(define-data-var minimum-reviewers uint u3)
(define-data-var review-period uint u1440) ;; blocks, roughly 10 days

;; Research submission structure
(define-map research-submissions
    { submission-id: uint }
    {
        researcher: principal,
        ipfs-hash: (string-ascii 46),  ;; IPFS hash of research data
        timestamp: uint,
        status: (string-ascii 20),     ;; pending, under-review, validated, rejected
        methodology-hash: (string-ascii 46),
        required-replications: uint,
        current-replications: uint
    }
)

;; Peer review tracking
(define-map peer-reviews
    { submission-id: uint, reviewer: principal }
    {
        review-hash: (string-ascii 46),
        timestamp: uint,
        verdict: (string-ascii 10),     ;; approve/reject
        credentials: (string-ascii 64)   ;; reviewer credentials hash
    }
)

;; Replication attempts tracking
(define-map replications
    { submission-id: uint, replicator: principal }
    {
        results-hash: (string-ascii 46),
        timestamp: uint,
        success: bool,
        methodology-variations: (string-ascii 64)
    }
)

;; Read-only functions
(define-read-only (get-submission (submission-id uint))
    (map-get? research-submissions { submission-id: submission-id })
)

(define-read-only (get-peer-review (submission-id uint) (reviewer principal))
    (map-get? peer-reviews { submission-id: submission-id, reviewer: reviewer })
)

(define-read-only (get-replication (submission-id uint) (replicator principal))
    (map-get? replications { submission-id: submission-id, replicator: replicator })
)

;; Validation functions
(define-private (validate-ipfs-hash (hash (string-ascii 46)))
    (begin
        (asserts! (> (len hash) u0) ERR-INVALID-IPFS-HASH)
        (asserts! (is-eq (slice? hash 0 2) "Qm") ERR-INVALID-IPFS-HASH)
        (ok true)
    )
)

;; Submit new research
(define-public (submit-research (ipfs-hash (string-ascii 46)) 
                              (methodology-hash (string-ascii 46))
                              (required-replications uint))
    (let
        (
            (submission-id (var-get next-submission-id))
        )
        ;; Increment the submission ID counter
        (var-set next-submission-id (+ submission-id u1))
        
        (map-set research-submissions
            { submission-id: submission-id }
            {
                researcher: tx-sender,
                ipfs-hash: ipfs-hash,
                timestamp: block-height,
                status: "pending",
                methodology-hash: methodology-hash,
                required-replications: required-replications,
                current-replications: u0
            }
        )
        (ok submission-id)
    )
)

;; Submit peer review
(define-public (submit-peer-review (submission-id uint)
                                 (review-hash (string-ascii 46))
                                 (verdict (string-ascii 10))
                                 (credentials (string-ascii 64)))
    (let
        (
            (submission (unwrap! (get-submission submission-id) ERR-NOT-FOUND))
        )
        ;; Check submission status
        (asserts! (is-eq (get status submission) "pending") ERR-INVALID-STATUS)
        
        (map-set peer-reviews
            { submission-id: submission-id, reviewer: tx-sender }
            {
                review-hash: review-hash,
                timestamp: block-height,
                verdict: verdict,
                credentials: credentials
            }
        )
        (ok true)
    )
)

;; Submit replication attempt
(define-public (submit-replication (submission-id uint)
                                 (results-hash (string-ascii 46))
                                 (success bool)
                                 (methodology-variations (string-ascii 64)))
    (let
        (
            (submission (unwrap! (get-submission submission-id) ERR-NOT-FOUND))
        )
        ;; Check submission status
        (asserts! (is-eq (get status submission) "under-review") ERR-INVALID-STATUS)
        
        (map-set replications
            { submission-id: submission-id, replicator: tx-sender }
            {
                results-hash: results-hash,
                timestamp: block-height,
                success: success,
                methodology-variations: methodology-variations
            }
        )
        (ok true)
    )
)

;; Administrative functions
(define-public (update-minimum-reviewers (new-minimum uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (var-set minimum-reviewers new-minimum)
        (ok true)
    )
)

(define-public (update-review-period (new-period uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (var-set review-period new-period)
        (ok true)
    )
)
