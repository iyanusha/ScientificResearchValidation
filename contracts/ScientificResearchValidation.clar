;; ScientificResearchValidation
;; Scientific research validation and peer review system on Stacks

;; Error Constants
(define-constant ERR-NOT-AUTHORIZED (err u401))
(define-constant ERR-NOT-FOUND (err u404))
(define-constant ERR-INVALID-STATUS (err u400))
(define-constant ERR-INVALID-IPFS-HASH (err u403))
(define-constant ERR-INVALID-METHODOLOGY (err u405))
(define-constant ERR-INVALID-REPLICATIONS (err u406))
(define-constant ERR-INVALID-CREDENTIALS (err u407))
(define-constant ERR-INVALID-VERDICT (err u408))
(define-constant ERR-DUPLICATE-REVIEW (err u409))
(define-constant ERR-INVALID-REVIEWER (err u410))
(define-constant ERR-INSUFFICIENT-REVIEWS (err u411))

;; Other Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant MAX-REPLICATIONS u100)
(define-constant VALID-STATUS (list "pending" "under-review" "validated" "rejected"))

;; Data Variables
(define-data-var next-submission-id uint u1)
(define-data-var minimum-reviewers uint u3)
(define-data-var review-period uint u1440) ;; blocks, roughly 10 days

;; Data Maps
(define-map research-submissions
    { submission-id: uint }
    {
        researcher: principal,
        ipfs-hash: (string-ascii 46),
        timestamp: uint,
        status: (string-ascii 20),
        methodology-hash: (string-ascii 46),
        required-replications: uint,
        current-replications: uint,
        review-count: uint
    }
)

(define-map peer-reviews
    { submission-id: uint, reviewer: principal }
    {
        review-hash: (string-ascii 46),
        timestamp: uint,
        verdict: (string-ascii 10),
        credentials: (string-ascii 64)
    }
)

(define-map replications
    { submission-id: uint, replicator: principal }
    {
        results-hash: (string-ascii 46),
        timestamp: uint,
        success: bool,
        methodology-variations: (string-ascii 64)
    }
)

;; Validation Functions
(define-private (validate-ipfs-hash (hash (string-ascii 46)))
    (begin
        (asserts! (> (len hash) u2) ERR-INVALID-IPFS-HASH)
        ;; Check if starts with "Qm"
        (asserts! (and 
            (is-eq (get charAt hash u0) "Q")
            (is-eq (get charAt hash u1) "m")
        ) ERR-INVALID-IPFS-HASH)
        (ok true)
    )
)

(define-private (validate-methodology-hash (hash (string-ascii 46)))
    (begin
        (asserts! (> (len hash) u0) ERR-INVALID-METHODOLOGY)
        (ok true)
    )
)

(define-private (validate-replications (count uint))
    (begin
        (asserts! (and (> count u0) (<= count MAX-REPLICATIONS)) ERR-INVALID-REPLICATIONS)
        (ok true)
    )
)

(define-private (validate-credentials (creds (string-ascii 64)))
    (begin
        (asserts! (> (len creds) u0) ERR-INVALID-CREDENTIALS)
        (ok true)
    )
)

(define-private (validate-verdict (v (string-ascii 10)))
    (begin
        (asserts! (or (is-eq v "approve") (is-eq v "reject")) ERR-INVALID-VERDICT)
        (ok true)
    )
)

;; Read-only Functions
(define-read-only (get-submission (submission-id uint))
    (map-get? research-submissions { submission-id: submission-id })
)

(define-read-only (get-peer-review (submission-id uint) (reviewer principal))
    (map-get? peer-reviews { submission-id: submission-id, reviewer: reviewer })
)

(define-read-only (get-replication (submission-id uint) (replicator principal))
    (map-get? replications { submission-id: submission-id, replicator: replicator })
)

(define-read-only (get-submission-status (submission-id uint))
    (match (get-submission submission-id)
        submission (ok (get status submission))
        ERR-NOT-FOUND
    )
)

;; Public Functions
(define-public (submit-research (ipfs-hash (string-ascii 46)) 
                              (methodology-hash (string-ascii 46))
                              (required-replications uint))
    (begin
        (try! (validate-ipfs-hash ipfs-hash))
        (try! (validate-methodology-hash methodology-hash))
        (try! (validate-replications required-replications))
        
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
                    current-replications: u0,
                    review-count: u0
                }
            )
            (ok submission-id)
        )
    )
)

(define-public (submit-peer-review (submission-id uint)
                                 (review-hash (string-ascii 46))
                                 (verdict (string-ascii 10))
                                 (credentials (string-ascii 64)))
    (begin
        (try! (validate-ipfs-hash review-hash))
        (try! (validate-verdict verdict))
        (try! (validate-credentials credentials))
        
        (let
            (
                (submission (unwrap! (get-submission submission-id) ERR-NOT-FOUND))
            )
            ;; Verify submission status
            (asserts! (is-eq (get status submission) "pending") ERR-INVALID-STATUS)
            ;; Verify reviewer hasn't reviewed before
            (asserts! (is-none (get-peer-review submission-id tx-sender)) ERR-DUPLICATE-REVIEW)
            
            (map-set peer-reviews
                { submission-id: submission-id, reviewer: tx-sender }
                {
                    review-hash: review-hash,
                    timestamp: block-height,
                    verdict: verdict,
                    credentials: credentials
                }
            )
            
            ;; Update review count
            (map-set research-submissions
                { submission-id: submission-id }
                (merge submission { review-count: (+ (get review-count submission) u1) })
            )
            
            (ok true)
        )
    )
)

(define-public (submit-replication (submission-id uint)
                                 (results-hash (string-ascii 46))
                                 (success bool)
                                 (methodology-variations (string-ascii 64)))
    (begin
        (try! (validate-ipfs-hash results-hash))
        
        (let
            (
                (submission (unwrap! (get-submission submission-id) ERR-NOT-FOUND))
            )
            ;; Verify submission status
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
            
            ;; Update replication count
            (map-set research-submissions
                { submission-id: submission-id }
                (merge submission { current-replications: (+ (get current-replications submission) u1) })
            )
            
            (ok true)
        )
    )
)

;; Administrative Functions
(define-public (update-minimum-reviewers (new-minimum uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (asserts! (> new-minimum u0) ERR-INVALID-STATUS)
        (var-set minimum-reviewers new-minimum)
        (ok true)
    )
)

(define-public (update-review-period (new-period uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (asserts! (> new-period u0) ERR-INVALID-STATUS)
        (var-set review-period new-period)
        (ok true)
    )
)

;; Status Management Functions
(define-public (move-to-review-phase (submission-id uint))
    (let
        (
            (submission (unwrap! (get-submission submission-id) ERR-NOT-FOUND))
        )
        (asserts! (is-eq (get status submission) "pending") ERR-INVALID-STATUS)
        (asserts! (>= (get review-count submission) (var-get minimum-reviewers)) ERR-INSUFFICIENT-REVIEWS)
        
        (map-set research-submissions
            { submission-id: submission-id }
            (merge submission { status: "under-review" })
        )
        (ok true)
    )
)

(define-public (finalize-submission (submission-id uint) (final-status (string-ascii 20)))
    (let
        (
            (submission (unwrap! (get-submission submission-id) ERR-NOT-FOUND))
        )
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (asserts! (is-eq (get status submission) "under-review") ERR-INVALID-STATUS)
        (asserts! (or (is-eq final-status "validated") (is-eq final-status "rejected")) ERR-INVALID-STATUS)
        
        (map-set research-submissions
            { submission-id: submission-id }
            (merge submission { status: final-status })
        )
        (ok true)
    )
)
