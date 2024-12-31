;; Scientific Research Validation Platform
;; Handles peer review, experiment validation, and research timestamping

(define-data-var minimum-reviewers uint u3)
(define-data-var review-period uint u1440) ;; blocks, roughly 10 days

;; Research submission structure
(define-map research-submissions
    { submission-id: uint }
    {
        researcher-principal: principal,
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

;; Submit new research
(define-public (submit-research (ipfs-hash (string-ascii 46)) 
                              (methodology-hash (string-ascii 46))
                              (required-replications uint))
    (let
        (
            (submission-id (get-next-submission-id))
        )
        (try! (stx-transfer? u100 tx-sender (as-contract tx-sender)))
        (map-set research-submissions
            { submission-id: submission-id }
            {
                researcher-principal: tx-sender,
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
            (submission (unwrap! (map-get? research-submissions { submission-id: submission-id })
                (err u1)))
        )
        (asserts! (is-eq (get status submission) "pending") (err u2))
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
            (submission (unwrap! (map-get? research-submissions { submission-id: submission-id })
                (err u1)))
        )
        (asserts! (is-eq (get status submission) "under-review") (err u2))
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

;; Private functions
(define-private (get-next-submission-id)
    (default-to u1
        (get-next-id-by-type "submission")
    )
)
