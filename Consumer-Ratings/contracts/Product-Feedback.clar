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
(define-constant ERR-INVALID-INPUT u10)
(define-constant ERR-INVALID-NAME-LENGTH u11)
(define-constant ERR-INVALID-DETAILS-LENGTH u12)
(define-constant ERR-INVALID-PRODUCT-ID u13)
(define-constant ERR-INVALID-REVIEW-ID u14)

;; Validation constants
(define-constant RATING-MINIMUM u1)
(define-constant RATING-MAXIMUM u5)
(define-constant MAX-REVIEWS-PER-PAGE u20)
(define-constant MAX-NAME-LENGTH u50)
(define-constant MAX-DETAILS-LENGTH u500)

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

;; Check if a product exists
(define-private (product-exists (product-id uint))
  (is-some (map-get? product-registry { product-identifier: product-id }))
)

;; Check if a review exists
(define-private (review-exists (review-id uint))
  (is-some (map-get? review-registry { review-identifier: review-id }))
)

;; Validate rating is within bounds
(define-private (is-valid-rating (rating uint))
  (and (>= rating RATING-MINIMUM) (<= rating RATING-MAXIMUM))
)

;; Validate product ID
(define-private (is-valid-product-id (product-id uint))
  (and 
    (>= product-id u1)
    (< product-id (var-get product-id-counter))
    (product-exists product-id)
  )
)

;; Validate review ID
(define-private (is-valid-review-id (review-id uint))
  (and 
    (>= review-id u1) 
    (< review-id (var-get review-id-counter))
    (review-exists review-id)
  )
)

;; Validate string length for name
(define-private (is-valid-name (name (string-ascii 50)))
  (and 
    (> (len name) u0)
    (<= (len name) MAX-NAME-LENGTH)
  )
)

;; Validate string length for details
(define-private (is-valid-details (details (string-ascii 500)))
  (<= (len details) MAX-DETAILS-LENGTH)
)

;; Safe method to add a review to product index and update stats
(define-private (safe-index-review (product-id uint) (review-id uint) (score uint))
  (begin
    ;; Validate inputs before indexing
    (asserts! (is-valid-product-id product-id) false)
    (asserts! (is-valid-review-id review-id) false)
    (asserts! (is-valid-rating score) false)
    
    ;; Add to index
    (map-insert product-review-index 
      { product-identifier: product-id, review-identifier: review-id }
      { exists: true }
    )
    
    ;; Update stats
    (match (map-get? product-review-stats { product-identifier: product-id })
      prev-stats (map-set product-review-stats 
                  { product-identifier: product-id }
                  { 
                    review-count: (+ (get review-count prev-stats) u1),
                    rating-sum: (+ (get rating-sum prev-stats) score)
                  })
      (map-insert product-review-stats 
        { product-identifier: product-id }
        { review-count: u1, rating-sum: score })
    )
    
    ;; Add to pages
    (let 
      (
        (stats (unwrap-panic (map-get? product-review-stats { product-identifier: product-id })))
        (count (get review-count stats))
        (page-number (/ (- count u1) MAX-REVIEWS-PER-PAGE))
        (page-offset (mod (- count u1) MAX-REVIEWS-PER-PAGE))
      )
      (match (map-get? product-review-pages { product-identifier: product-id, page-number: page-number })
        existing-page 
          ;; Check if we have room in the current page
          (if (< (len (get review-ids existing-page)) MAX-REVIEWS-PER-PAGE)
            ;; If we have room, add to current page
            (map-set product-review-pages
              { product-identifier: product-id, page-number: page-number }
              { review-ids: (unwrap-panic 
                  (as-max-len? 
                    (append (get review-ids existing-page) review-id) 
                    u20)) })
            ;; If page is full, create a new page
            (map-insert product-review-pages
              { product-identifier: product-id, page-number: (+ u1 page-number) }
              { review-ids: (list review-id) }))
        ;; If page doesn't exist yet, create it
        (map-insert product-review-pages
          { product-identifier: product-id, page-number: page-number }
          { review-ids: (list review-id) })
      )
    )
    
    true
  )
)

;; Check if a review belongs to a product
(define-private (is-review-for-product (product-id uint) (review-id uint))
  (default-to 
    false
    (get exists (map-get? product-review-index { product-identifier: product-id, review-identifier: review-id }))
  )
)

;; Update product review stats when removing a review
(define-private (update-stats-on-review-removal (product-id uint) (review-score uint))
  (begin
    ;; Validate inputs
    (asserts! (is-valid-product-id product-id) false)
    (asserts! (is-valid-rating review-score) false)
    
    (match (map-get? product-review-stats { product-identifier: product-id })
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
            { product-identifier: product-id }
            { review-count: new-count, rating-sum: new-sum })
          true
        )
      false
    )
  )
)

;; Read-Only Functions

;; Retrieve product information by ID
(define-read-only (get-product-details (product-id uint))
  (if (is-valid-product-id product-id)
    (map-get? product-registry { product-identifier: product-id })
    none
  )
)

;; Retrieve review information by ID
(define-read-only (get-review-details (review-id uint))
  (if (is-valid-review-id review-id)
    (map-get? review-registry { review-identifier: review-id })
    none
  )
)

;; Check if caller has administrative privileges
(define-read-only (is-contract-owner)
  (is-eq tx-sender (var-get contract-owner))
)

;; Get product review stats
(define-read-only (get-product-review-stats (product-id uint))
  (if (is-valid-product-id product-id)
    (default-to 
      { review-count: u0, rating-sum: u0 } 
      (map-get? product-review-stats { product-identifier: product-id }))
    { review-count: u0, rating-sum: u0 }
  )
)

;; Calculate average rating for a product
(define-read-only (calculate-average-rating (product-id uint))
  (let 
    (
      (stats (get-product-review-stats product-id))
      (count (get review-count stats))
      (sum (get rating-sum stats))
    )
    (if (> count u0)
      (/ sum count)
      u0)
  )
)

;; Get total number of pages for a product's reviews
(define-read-only (get-total-review-pages (product-id uint))
  (let 
    (
      (stats (get-product-review-stats product-id))
      (count (get review-count stats))
    )
    (+ (/ count MAX-REVIEWS-PER-PAGE) 
       (if (> (mod count MAX-REVIEWS-PER-PAGE) u0) u1 u0))
  )
)

;; Get product reviews by page
(define-read-only (get-product-reviews-page (product-id uint) (page-number uint))
  (if (not (is-valid-product-id product-id))
    { review-ids: (list) }
    (let 
      (
        (total-pages (get-total-review-pages product-id))
      )
      (if (or (>= page-number total-pages) (is-eq total-pages u0))
        { review-ids: (list) }
        (default-to 
          { review-ids: (list) } 
          (map-get? product-review-pages { product-identifier: product-id, page-number: page-number }))
      )
    )
  )
)

;; Get expanded reviews for a page (with full review details)
(define-read-only (get-product-reviews (product-id uint) (page-number uint))
  (if (not (is-valid-product-id product-id))
    (list)
    (let 
      (
        (page-data (get-product-reviews-page product-id page-number))
        (review-ids (get review-ids page-data))
        (review-details (map get-review-details review-ids))
      )
      ;; Since we can't directly filter with is-some, return all results
      ;; The None values will be returned as None
      review-details
    )
  )
)

;; Public Functions

;; Register a new product
(define-public (register-product (name (string-ascii 50)) (details (string-ascii 500)))
  (let
    (
      (new-product-id (var-get product-id-counter))
    )
    ;; Validate inputs
    (asserts! (is-valid-name name) (err ERR-INVALID-NAME-LENGTH))
    (asserts! (is-valid-details details) (err ERR-INVALID-DETAILS-LENGTH))
    
    ;; Verify administrative privileges
    (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR-NOT-CONTRACT-OWNER))
    
    ;; Increment product identifier counter
    (var-set product-id-counter (+ new-product-id u1))
    
    ;; Register the product in the catalog
    (ok (map-insert product-registry 
      { product-identifier: new-product-id }
      {
        product-name: name,
        product-details: details,
        product-creator: tx-sender,
        registration-block: block-height,
        product-status: true
      }
    ))
  )
)

;; Modify existing product information
(define-public (update-product-details (id uint) 
                                      (name (string-ascii 50)) 
                                      (details (string-ascii 500)) 
                                      (status bool))
  (begin
    ;; Validate inputs
    (asserts! (is-valid-product-id id) (err ERR-INVALID-PRODUCT-ID))
    (asserts! (is-valid-name name) (err ERR-INVALID-NAME-LENGTH))
    (asserts! (is-valid-details details) (err ERR-INVALID-DETAILS-LENGTH))
    
    (let
      (
        (existing-product (map-get? product-registry { product-identifier: id }))
      )
      ;; Validate product exists
      (asserts! (is-some existing-product) (err ERR-PRODUCT-NOT-REGISTERED))
      
      ;; Verify authorization (contract owner or original manufacturer)
      (asserts! (or 
        (is-eq tx-sender (var-get contract-owner))
        (is-eq tx-sender (get product-creator (unwrap-panic existing-product)))
      ) (err ERR-INSUFFICIENT-PERMISSIONS))
      
      ;; Update product information
      (ok (map-set product-registry
        { product-identifier: id }
        {
          product-name: name,
          product-details: details,
          product-creator: (get product-creator (unwrap-panic existing-product)),
          registration-block: (get registration-block (unwrap-panic existing-product)),
          product-status: status
        }
      ))
    )
  )
)

;; Submit a product review
(define-public (submit-product-review (product-id uint) 
                                     (score uint) 
                                     (content (string-ascii 500)) 
                                     (purchase-verification bool))
  (begin
    ;; Validate inputs
    (asserts! (is-valid-product-id product-id) (err ERR-INVALID-PRODUCT-ID))
    (asserts! (is-valid-rating score) (err ERR-INVALID-RATING-VALUE))
    (asserts! (is-valid-details content) (err ERR-INVALID-DETAILS-LENGTH))
    
    (let
      (
        (new-review-id (var-get review-id-counter))
        (product-info (map-get? product-registry { product-identifier: product-id }))
      )
      ;; Validate product exists and is active
      (asserts! (is-some product-info) (err ERR-PRODUCT-NOT-REGISTERED))
      (asserts! (get product-status (unwrap-panic product-info)) (err ERR-INACTIVE-PRODUCT))
      
      ;; Increment review ID counter
      (var-set review-id-counter (+ new-review-id u1))
      
      ;; Store the review
      (begin
        (map-insert review-registry
          { review-identifier: new-review-id }
          {
            product-identifier: product-id,
            review-author: tx-sender,
            review-score: score,
            review-content: content,
            review-timestamp: block-height,
            purchase-verification: purchase-verification
          }
        )
        
        ;; Index the review for efficient filtering
        (asserts! (safe-index-review product-id new-review-id score) (err ERR-UNKNOWN-OPERATION))
        
        (ok new-review-id)
      )
    )
  )
)

;; Modify an existing review
(define-public (update-review-content (review-id uint) 
                                     (score uint) 
                                     (content (string-ascii 500)))
  (begin
    ;; Validate inputs
    (asserts! (is-valid-review-id review-id) (err ERR-INVALID-REVIEW-ID))
    (asserts! (is-valid-rating score) (err ERR-INVALID-RATING-VALUE))
    (asserts! (is-valid-details content) (err ERR-INVALID-DETAILS-LENGTH))
    
    (let
      (
        (existing-review (map-get? review-registry { review-identifier: review-id }))
      )
      ;; Validate review exists
      (asserts! (is-some existing-review) (err ERR-REVIEW-NOT-FOUND))
      
      ;; Verify authorization (must be original reviewer)
      (asserts! (is-eq tx-sender (get review-author (unwrap-panic existing-review))) 
                (err ERR-INSUFFICIENT-PERMISSIONS))
      
      ;; Update product stats with rating change
      (let 
        (
          (old-review (unwrap-panic existing-review))
          (old-score (get review-score old-review))
          (product-id (get product-identifier old-review))
          (stats (unwrap-panic (map-get? product-review-stats { product-identifier: product-id })))
          (old-sum (get rating-sum stats))
          (new-sum (+ (- old-sum old-score) score))
        )
        ;; Update stats
        (map-set product-review-stats 
          { product-identifier: product-id }
          { review-count: (get review-count stats), rating-sum: new-sum }
        )
        
        ;; Update the review content
        (ok (map-set review-registry
          { review-identifier: review-id }
          {
            product-identifier: product-id,
            review-author: tx-sender,
            review-score: score,
            review-content: content,
            review-timestamp: (get review-timestamp old-review),
            purchase-verification: (get purchase-verification old-review)
          }
        ))
      )
    )
  )
)

;; Remove a review from the system
(define-public (remove-review (review-id uint))
  (begin
    ;; Validate inputs
    (asserts! (is-valid-review-id review-id) (err ERR-INVALID-REVIEW-ID))
    
    (let
      (
        (existing-review (map-get? review-registry { review-identifier: review-id }))
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
        (asserts! (update-stats-on-review-removal product-id review-score) (err ERR-UNKNOWN-OPERATION))
        
        ;; Delete the review and remove from index
        (begin
          (map-delete review-registry { review-identifier: review-id })
          (map-delete product-review-index { 
            product-identifier: product-id, 
            review-identifier: review-id 
          })
          (ok true)
        )
      )
    )
  )
)

;; Transfer contract ownership
(define-public (transfer-contract-ownership (new-owner principal))
  (begin
    ;; Validate owner
    (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR-NOT-CONTRACT-OWNER))
    
    ;; Validate new owner is not null/zero address
    (asserts! (not (is-eq new-owner 'SP000000000000000000002Q6VF78)) (err ERR-INVALID-INPUT))
    
    ;; Transfer ownership
    (var-set contract-owner new-owner)
    (ok true)
  )
)