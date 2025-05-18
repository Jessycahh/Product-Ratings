;; Product Review Registry - Decentralized Review Management System

;; This smart contract enables a decentralized product review ecosystem where:
;; - Manufacturers can register and manage their products
;; - Users can submit verified reviews with ratings and comments
;; - Reviews are stored permanently and transparently on the blockchain
;; - Review authenticity can be verified through ownership validation

;; Constants

;; Error constants
(define-constant ERR-NOT-CONTRACT-OWNER u1)
(define-constant ERR-PRODUCT-NOT-REGISTERED u2)
(define-constant ERR-INSUFFICIENT-PERMISSIONS u3)
(define-constant ERR-INVALID-RATING-VALUE u4)
(define-constant ERR-REVIEW-NOT-FOUND u5)
(define-constant ERR-PRODUCT-ALREADY-EXISTS u6)
(define-constant ERR-INACTIVE-PRODUCT u7)
(define-constant ERR-UNKNOWN-OPERATION u8)
(define-constant ERR-INVALID-PAGE u9)

;; Validation constants
(define-constant RATING-MINIMUM u1)
(define-constant RATING-MAXIMUM u5)
(define-constant MAX-REVIEWS-PER-PAGE u20)

;; Data Variables

;; Contract ownership management
(define-data-var contract-owner principal tx-sender)

;; ID counters for sequential assignment
(define-data-var product-id-counter uint u1)
(define-data-var review-id-counter uint u1)

;; Data Structures

;; Product catalog storage
(define-map product-registry
  { product-identifier: uint }
  {
    product-name: (string-ascii 50),
    product-details: (string-ascii 500),
    product-creator: principal,
    registration-block: uint,
    product-status: bool
  }
)

;; Review repository storage
(define-map review-registry
  { review-identifier: uint }
  {
    product-identifier: uint,
    review-author: principal,
    review-score: uint,
    review-content: (string-ascii 500),
    review-timestamp: uint,
    purchase-verification: bool
  }
)

;; Track product to review mappings
(define-map product-review-index
  { product-identifier: uint, review-identifier: uint }
  { exists: bool }
)

;; Track product review stats
(define-map product-review-stats
  { product-identifier: uint }
  { 
    review-count: uint, 
    rating-sum: uint 
  }
)

;; Track reviews by page (up to 20 reviews per page)
(define-map product-review-pages
  { product-identifier: uint, page-number: uint }
  { review-ids: (list 20 uint) }
)

;; Private Helper Functions

;; Add review to product index and update stats
(define-private (index-review (product-identifier uint) (review-identifier uint) (review-score uint))
  (begin
    ;; Add to index
    (map-insert product-review-index 
      { product-identifier: product-identifier, review-identifier: review-identifier }
      { exists: true }
    )
    
    ;; Update stats
    (match (map-get? product-review-stats { product-identifier: product-identifier })
      prev-stats (map-set product-review-stats 
                  { product-identifier: product-identifier }
                  { 
                    review-count: (+ (get review-count prev-stats) u1),
                    rating-sum: (+ (get rating-sum prev-stats) review-score)
                  })
      (map-insert product-review-stats 
        { product-identifier: product-identifier }
        { review-count: u1, rating-sum: review-score })
    )
    
    ;; Add to pages
    (let 
      (
        (stats (unwrap-panic (map-get? product-review-stats { product-identifier: product-identifier })))
        (count (get review-count stats))
        (page-number (/ (- count u1) MAX-REVIEWS-PER-PAGE))
        (page-offset (mod (- count u1) MAX-REVIEWS-PER-PAGE))
      )
      (match (map-get? product-review-pages { product-identifier: product-identifier, page-number: page-number })
        existing-page 
          ;; Check if we have room in the current page
          (if (< (len (get review-ids existing-page)) MAX-REVIEWS-PER-PAGE)
            ;; If we have room, add to current page
            (map-set product-review-pages
              { product-identifier: product-identifier, page-number: page-number }
              { review-ids: (unwrap-panic 
                  (as-max-len? 
                    (append (get review-ids existing-page) review-identifier) 
                    u20)) })
            ;; If page is full, create a new page
            (map-insert product-review-pages
              { product-identifier: product-identifier, page-number: (+ u1 page-number) }
              { review-ids: (list review-identifier) }))
        ;; If page doesn't exist yet, create it
        (map-insert product-review-pages
          { product-identifier: product-identifier, page-number: page-number }
          { review-ids: (list review-identifier) })
      )
    )
  )
)

;; Check if a review belongs to a product
(define-private (is-review-for-product (product-identifier uint) (review-identifier uint))
  (default-to 
    false
    (get exists (map-get? product-review-index { product-identifier: product-identifier, review-identifier: review-identifier }))
  )
)

;; Update product review stats when removing a review
(define-private (update-stats-on-review-removal (product-identifier uint) (review-score uint))
  (match (map-get? product-review-stats { product-identifier: product-identifier })
    prev-stats 
      (let 
        (
          (new-count (if (> (get review-count prev-stats) u0) 
                       (- (get review-count prev-stats) u1) 
                       u0))
          (new-sum (if (>= (get rating-sum prev-stats) review-score)
                     (- (get rating-sum prev-stats) review-score)
                     u0))
        )
        (map-set product-review-stats 
          { product-identifier: product-identifier }
          { review-count: new-count, rating-sum: new-sum })
      )
    false
  )
)

;; Read-Only Functions

;; Retrieve product information by ID
(define-read-only (get-product-details (product-identifier uint))
  (map-get? product-registry { product-identifier: product-identifier })
)

;; Retrieve review information by ID
(define-read-only (get-review-details (review-identifier uint))
  (map-get? review-registry { review-identifier: review-identifier })
)

;; Check if caller has administrative privileges
(define-read-only (is-contract-owner)
  (is-eq tx-sender (var-get contract-owner))
)

;; Get product review stats
(define-read-only (get-product-review-stats (product-identifier uint))
  (default-to 
    { review-count: u0, rating-sum: u0 } 
    (map-get? product-review-stats { product-identifier: product-identifier }))
)

;; Calculate average rating for a product
(define-read-only (calculate-average-rating (product-identifier uint))
  (let 
    (
      (stats (get-product-review-stats product-identifier))
      (count (get review-count stats))
      (sum (get rating-sum stats))
    )
    (if (> count u0)
      (/ sum count)
      u0)
  )
)

;; Get total number of pages for a product's reviews
(define-read-only (get-total-review-pages (product-identifier uint))
  (let 
    (
      (stats (get-product-review-stats product-identifier))
      (count (get review-count stats))
    )
    (+ (/ count MAX-REVIEWS-PER-PAGE) 
       (if (> (mod count MAX-REVIEWS-PER-PAGE) u0) u1 u0))
  )
)

;; Get product reviews by page
(define-read-only (get-product-reviews-page (product-identifier uint) (page-number uint))
  (let 
    (
      (total-pages (get-total-review-pages product-identifier))
    )
    (if (or (>= page-number total-pages) (is-eq total-pages u0))
      (tuple (review-ids (list)))
      (default-to 
        { review-ids: (list) } 
        (map-get? product-review-pages { product-identifier: product-identifier, page-number: page-number }))
    )
  )
)

;; Get expanded reviews for a page (with full review details)
(define-read-only (get-product-reviews (product-identifier uint) (page-number uint))
  (let 
    (
      (page-data (get-product-reviews-page product-identifier page-number))
      (review-ids (get review-ids page-data))
    )
    (map get-review-details review-ids)
  )
)

;; Public Functions

;; Register a new product
(define-public (register-product (product-name (string-ascii 50)) (product-details (string-ascii 500)))
  (let
    (
      (new-product-id (var-get product-id-counter))
    )
    ;; Verify administrative privileges
    (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR-NOT-CONTRACT-OWNER))
    
    ;; Increment product identifier counter
    (var-set product-id-counter (+ new-product-id u1))
    
    ;; Register the product in the catalog
    (ok (map-insert product-registry 
      { product-identifier: new-product-id }
      {
        product-name: product-name,
        product-details: product-details,
        product-creator: tx-sender,
        registration-block: block-height,
        product-status: true
      }
    ))
  )
)

;; Modify existing product information
(define-public (update-product-details (product-identifier uint) 
                                      (product-name (string-ascii 50)) 
                                      (product-details (string-ascii 500)) 
                                      (product-status bool))
  (let
    (
      (existing-product (map-get? product-registry { product-identifier: product-identifier }))
    )
    ;; Validate product existence
    (asserts! (is-some existing-product) (err ERR-PRODUCT-NOT-REGISTERED))
    
    ;; Verify authorization (contract owner or original manufacturer)
    (asserts! (or 
      (is-eq tx-sender (var-get contract-owner))
      (is-eq tx-sender (get product-creator (unwrap-panic existing-product)))
    ) (err ERR-INSUFFICIENT-PERMISSIONS))
    
    ;; Update product information
    (ok (map-set product-registry
      { product-identifier: product-identifier }
      {
        product-name: product-name,
        product-details: product-details,
        product-creator: (get product-creator (unwrap-panic existing-product)),
        registration-block: (get registration-block (unwrap-panic existing-product)),
        product-status: product-status
      }
    ))
  )
)

;; Submit a product review
(define-public (submit-product-review (product-identifier uint) 
                                     (review-score uint) 
                                     (review-content (string-ascii 500)) 
                                     (purchase-verification bool))
  (let
    (
      (new-review-id (var-get review-id-counter))
      (product-info (map-get? product-registry { product-identifier: product-identifier }))
    )
    ;; Validate product exists and is active
    (asserts! (is-some product-info) (err ERR-PRODUCT-NOT-REGISTERED))
    (asserts! (get product-status (unwrap-panic product-info)) (err ERR-INACTIVE-PRODUCT))
    
    ;; Validate rating is within allowed range
    (asserts! (and (>= review-score RATING-MINIMUM) (<= review-score RATING-MAXIMUM)) 
              (err ERR-INVALID-RATING-VALUE))
    
    ;; Increment review ID counter
    (var-set review-id-counter (+ new-review-id u1))
    
    ;; Store the review
    (begin
      (map-insert review-registry
        { review-identifier: new-review-id }
        {
          product-identifier: product-identifier,
          review-author: tx-sender,
          review-score: review-score,
          review-content: review-content,
          review-timestamp: block-height,
          purchase-verification: purchase-verification
        }
      )
      
      ;; Index the review for efficient filtering
      (index-review product-identifier new-review-id review-score)
      
      (ok new-review-id)
    )
  )
)

;; Modify an existing review
(define-public (update-review-content (review-identifier uint) 
                                     (review-score uint) 
                                     (review-content (string-ascii 500)))
  (let
    (
      (existing-review (map-get? review-registry { review-identifier: review-identifier }))
    )
    ;; Validate review exists
    (asserts! (is-some existing-review) (err ERR-REVIEW-NOT-FOUND))
    
    ;; Verify authorization (must be original reviewer)
    (asserts! (is-eq tx-sender (get review-author (unwrap-panic existing-review))) 
              (err ERR-INSUFFICIENT-PERMISSIONS))
    
    ;; Validate rating is within allowed range
    (asserts! (and (>= review-score RATING-MINIMUM) (<= review-score RATING-MAXIMUM)) 
              (err ERR-INVALID-RATING-VALUE))
    
    ;; Update product stats with rating change
    (let 
      (
        (old-review (unwrap-panic existing-review))
        (old-score (get review-score old-review))
        (product-id (get product-identifier old-review))
        (stats (unwrap-panic (map-get? product-review-stats { product-identifier: product-id })))
        (old-sum (get rating-sum stats))
        (new-sum (+ (- old-sum old-score) review-score))
      )
      ;; Update stats
      (map-set product-review-stats 
        { product-identifier: product-id }
        { review-count: (get review-count stats), rating-sum: new-sum }
      )
      
      ;; Update the review content
      (ok (map-set review-registry
        { review-identifier: review-identifier }
        {
          product-identifier: product-id,
          review-author: tx-sender,
          review-score: review-score,
          review-content: review-content,
          review-timestamp: (get review-timestamp old-review),
          purchase-verification: (get purchase-verification old-review)
        }
      ))
    )
  )
)

;; Remove a review from the system
(define-public (remove-review (review-identifier uint))
  (let
    (
      (existing-review (map-get? review-registry { review-identifier: review-identifier }))
    )
    ;; Validate review exists
    (asserts! (is-some existing-review) (err ERR-REVIEW-NOT-FOUND))
    
    ;; Verify authorization (contract owner or original reviewer)
    (asserts! (or 
      (is-eq tx-sender (var-get contract-owner))
      (is-eq tx-sender (get review-author (unwrap-panic existing-review)))
    ) (err ERR-INSUFFICIENT-PERMISSIONS))
    
    ;; Update stats and remove review
    (let
      (
        (review (unwrap-panic existing-review))
        (product-id (get product-identifier review))
        (review-score (get review-score review))
      )
      ;; Update product stats
      (update-stats-on-review-removal product-id review-score)
      
      ;; Delete the review and remove from index
      (begin
        (map-delete review-registry { review-identifier: review-identifier })
        (map-delete product-review-index { 
          product-identifier: product-id, 
          review-identifier: review-identifier 
        })
        (ok true)
      )
    )
  )
)

;; Transfer contract ownership
(define-public (transfer-contract-ownership (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR-NOT-CONTRACT-OWNER))
    (var-set contract-owner new-owner)
    (ok true)
  )
)