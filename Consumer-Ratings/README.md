# Product Review Registry

## Overview

The Product Review Registry is a decentralized smart contract system that enables transparent and immutable product reviews on the blockchain. This system allows manufacturers to register products and users to submit verified reviews, creating a trustworthy ecosystem for product feedback.

## Features

- **Decentralized Review Management**: All reviews are stored permanently on the blockchain
- **Manufacturer Dashboard**: Product owners can register and manage their products
- **Verified Reviews**: Users can submit reviews with ratings (1-5 stars) and comments
- **Review Authenticity**: Review ownership is validated through blockchain verification
- **Pagination Support**: Efficiently browse product reviews with built-in pagination
- **Rating Statistics**: Track and display aggregate product ratings

## Contract Functions

### Administrative Functions

| Function | Description | Accessibility |
|----------|-------------|--------------|
| `register-product` | Register a new product in the system | Contract Owner |
| `update-product-details` | Modify existing product information | Contract Owner or Product Creator |
| `transfer-contract-ownership` | Transfer ownership of the contract | Contract Owner |

### User Functions

| Function | Description | Accessibility |
|----------|-------------|--------------|
| `submit-product-review` | Submit a new product review | Any User |
| `update-review-content` | Modify an existing review | Original Reviewer |
| `remove-review` | Remove a review from the system | Contract Owner or Original Reviewer |

### Read-Only Functions

| Function | Description |
|----------|-------------|
| `get-product-details` | Retrieve product information by ID |
| `get-review-details` | Retrieve review information by ID |
| `calculate-average-rating` | Calculate the average rating for a product |
| `get-product-review-stats` | Get review statistics for a product |
| `get-product-reviews-page` | Get paginated reviews for a product |
| `get-product-reviews` | Get expanded reviews with full details |
| `get-total-review-pages` | Get the total number of review pages for a product |

## Data Structures

The contract uses several data maps to organize information:

- `product-registry`: Stores product details like name, description, and status
- `review-registry`: Stores review content, ratings, and verification status
- `product-review-index`: Maps products to their reviews
- `product-review-stats`: Tracks review counts and rating sums for products
- `product-review-pages`: Organizes reviews into pages for efficient retrieval

## Error Codes

| Code | Description |
|------|-------------|
| `ERR-NOT-CONTRACT-OWNER` | Operation requires contract owner privileges |
| `ERR-PRODUCT-NOT-REGISTERED` | Referenced product does not exist |
| `ERR-INSUFFICIENT-PERMISSIONS` | User lacks required permissions |
| `ERR-INVALID-RATING-VALUE` | Rating value outside valid range (1-5) |
| `ERR-REVIEW-NOT-FOUND` | Referenced review does not exist |
| `ERR-PRODUCT-ALREADY-EXISTS` | Product ID already registered |
| `ERR-INACTIVE-PRODUCT` | Product is currently inactive |
| `ERR-UNKNOWN-OPERATION` | Operation not recognized |
| `ERR-INVALID-PAGE` | Page number is invalid |

## Usage Examples

### Registering a Product

```clarity
;; Only contract owner can register products
(contract-call? .product-review-registry register-product "Premium Headphones" "Wireless noise-cancelling headphones with 30-hour battery life")
```

### Submitting a Review

```clarity
;; Any user can submit a review for a registered product
(contract-call? .product-review-registry submit-product-review u1 u5 "These headphones are amazing! Crystal clear sound and comfortable for long periods." true)
```

### Updating a Product

```clarity
;; Only the contract owner or product creator can update products
(contract-call? .product-review-registry update-product-details u1 "Premium Headphones v2" "Updated wireless headphones with 40-hour battery life and improved sound quality" true)
```

### Retrieving Product Statistics

```clarity
;; Read-only function to get product rating statistics
(contract-call? .product-review-registry get-product-review-stats u1)
;; Calculate average rating
(contract-call? .product-review-registry calculate-average-rating u1)
```

## Security Considerations

- All administrative functions are protected by ownership verification
- Review modifications are restricted to original authors
- Review ratings are validated to ensure they fall within the acceptable range
- Product status tracking prevents reviews on inactive products

## Implementation Notes

- The contract uses pagination to efficiently manage large sets of reviews
- Review statistics are updated in real-time when reviews are added, modified, or removed
- The contract tracks verified purchases to enhance review credibility
- All data is stored permanently on the blockchain for maximum transparency