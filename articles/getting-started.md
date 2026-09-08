# Getting started with unknown XML

``` r

library(xmlrectr)
```

## The core idea

`xmlrectr` separates structural evidence from the analytical decision.
The recommended workflow is:

``` text
proposal -> review -> profile -> rectangle
```

The proposal is deliberately not executable. It tells you what the
sample XML contains; you decide what a row means and which values belong
in the result.

## Inspect a sample

The package ships with a small XML example:

``` r

file <- system.file("extdata", "orders.xml", package = "xmlrectr")
proposal <- propose_xml_profile(file)
proposal
#> XML profile proposal (review only)
#>   Source: /home/runner/work/_temp/Library/xmlrectr/extdata/orders.xml
#>   Row candidates: 2
#>   Row used for proposal analysis: orders/order (heuristic_for_review)
#>   ID candidates: 3
#>   Field candidates: 11
#>   Sample-based non-character type suggestions: 2
#>   Nothing is executed or accepted automatically.
#>   Use review_xml_proposal() and then create an explicit xml_profile().
```

Review candidate row structures:

``` r

review_xml_proposal(proposal, "rows")
#> # A tibble: 2 × 10
#>   rows   namespace occurrences depth max_per_parent sample_repeated xsd_repeated
#>   <chr>  <chr>           <int> <int>          <int> <lgl>           <lgl>       
#> 1 order… urn:exam…           2     2              2 TRUE            FALSE       
#> 2 order… urn:exam…           3     3              2 TRUE            FALSE       
#> # ℹ 3 more variables: xsd_selector <chr>, priority <chr>, reason <chr>
```

Review possible identifiers and fields:

``` r

review_xml_proposal(proposal, "ids")
#> # A tibble: 3 × 4
#>   source        value_kind priority  reason                                     
#>   <chr>         <chr>      <chr>     <chr>                                      
#> 1 @id           attribute  strong    Complete, unique scalar attribute conventi…
#> 2 @status       attribute  plausible Complete, unique scalar attribute; semanti…
#> 3 customer/name text       possible  Complete, unique scalar value; semantics s…
review_xml_proposal(proposal, "fields")
#> # A tibble: 11 × 11
#>    source             value_kind entity records_observed coverage max_per_record
#>    <chr>              <chr>      <chr>             <int>    <dbl>          <int>
#>  1 @id                attribute  order                 2      1                1
#>  2 @status            attribute  order                 2      1                1
#>  3 customer/name      text       order                 2      1                1
#>  4 customer/postal-c… text       order                 1      0.5              1
#>  5 item/@sku          attribute  item                  2      1                2
#>  6 item/@quantity     attribute  item                  2      1                2
#>  7 item/description   text       item                  2      1                2
#>  8 item/unit-price/@… attribute  item                  2      1                2
#>  9 item/unit-price    text       item                  2      1                2
#> 10 note/@priority     attribute  order                 1      0.5              1
#> 11 note               text       order                 1      0.5              1
#> # ℹ 5 more variables: under_repetition <lgl>, wide_safe <lgl>,
#> #   sample_type <chr>, sample_confidence <chr>, sample_reason <chr>
```

## Define the profile

For this XML family, one `order` is the desired analytical row and its
`id` value identifies the record:

``` r

profile <- xml_profile(
  rows = "order",
  id = "id"
)
profile
#> XML rectangle profile
#>   Rows: order
#>   ID: id
#>   Fields: all values
#>   Types: all character
#>   Layout: safe (one atomic table)
```

A profile is intentionally small and human-readable. It can be stored as
JSON or YAML and reviewed independently from the code that executes it.

``` r

write_xml_profile(profile, "orders-profile.json")
profile <- read_xml_profile("orders-profile.json")
```

## Rectangle the XML

The simplest call can compile the profile against the file and apply it:

``` r

out <- rectangle_xml(file, profile)
out
#> # A tibble: 24 × 15
#>    document_id record_index record_id entity entity_index field      value_index
#>    <chr>              <int> <chr>     <chr>         <int> <chr>            <int>
#>  1 orders.xml             1 A-001     order             1 id                   1
#>  2 orders.xml             1 A-001     order             1 status               1
#>  3 orders.xml             1 A-001     order             1 customer/…           1
#>  4 orders.xml             1 A-001     order             1 customer/…           1
#>  5 orders.xml             1 A-001     item              1 sku                  1
#>  6 orders.xml             1 A-001     item              1 quantity             1
#>  7 orders.xml             1 A-001     item              1 descripti…           1
#>  8 orders.xml             1 A-001     item              1 unit-pric…           1
#>  9 orders.xml             1 A-001     item              1 unit-price           1
#> 10 orders.xml             1 A-001     item              2 sku                  1
#> # ℹ 14 more rows
#> # ℹ 8 more variables: value <chr>, value_kind <chr>, source <chr>,
#> #   record_node_id <int>, entity_node_id <int>, parent_entity_node_id <int>,
#> #   source_node_id <int>, source_path <chr>
```

For repeated processing of files from the same XML family, compile once
and reuse the specification:

``` r

spec <- compile_xml_profile(profile, file)
out2 <- rectangle_xml(file, spec)
identical(out, out2)
#> [1] TRUE
```

## Parallel execution is an option, not another workflow

The same function controls execution:

``` r

rectangle_xml(file, spec, parallel = FALSE)   # exact sequential path
rectangle_xml(file, spec, parallel = TRUE)    # request tuned parallel defaults
rectangle_xml(file, spec, parallel = "auto")  # engine chooses
```

`parallel = "auto"` is useful for ordinary work because small record
workloads stay sequential instead of paying process startup/scheduling
overhead.

## XSD-assisted review

If an XSD exists, it can provide additional occurrence/required/type
evidence:

``` r

typed_xml <- system.file("extdata", "types.xml", package = "xmlrectr")
typed_xsd <- system.file("extdata", "types.xsd", package = "xmlrectr")

xsd_proposal <- propose_xml_profile(typed_xml, xsd = typed_xsd)
review_xml_proposal(xsd_proposal, "xsd")
#> # A tibble: 9 × 11
#>   selector kind  name  type  builtin_type analytical_type type_source min_occurs
#>   <chr>    <chr> <chr> <chr> <chr>        <chr>           <chr>       <chr>     
#> 1 measure… elem… meas… NA    NA           NA              unresolved  1         
#> 2 measure… elem… meas… NA    NA           NA              unresolved  1         
#> 3 measure… elem… count xs:i… int          integer         type_attri… 1         
#> 4 measure… elem… ratio xs:d… double       double          type_attri… 1         
#> 5 measure… elem… acti… xs:b… boolean      logical         type_attri… 1         
#> 6 measure… elem… obse… xs:d… date         date            type_attri… 1         
#> 7 measure… elem… code  xs:s… string       character       type_attri… 1         
#> 8 measure… attr… id    xs:ID ID           character       type_attri… 0         
#> 9 custom   elem… cust… Loca… NA           NA              type_attri… 1         
#> # ℹ 3 more variables: max_occurs <chr>, repeated <lgl>, required <lgl>
```

XSD information is advisory. It does not automatically determine the
best analytical rectangle, and
[`inspect_xsd()`](https://larry77.github.io/xmlrectr/reference/inspect_xsd.md)
is not intended as a complete XSD validator.

## Exploratory analyst table

When you want one self-contained table quickly and do not yet need a
reusable profile contract:

``` r

analyst <- rectangle_xml_analyst(file)
analyst
#> # A tibble: 6 × 26
#>   xml_document_id xml_entity xml_entity_id xml_parent_entity
#>   <chr>           <chr>      <chr>         <chr>            
#> 1 orders.xml      orders     e000000002    NA               
#> 2 orders.xml      order      e000000004    orders           
#> 3 orders.xml      item       e000000012    order            
#> 4 orders.xml      item       e000000020    order            
#> 5 orders.xml      order      e000000031    orders           
#> 6 orders.xml      item       e000000037    order            
#> # ℹ 22 more variables: xml_parent_entity_id <chr>, xml_occurrence <int>,
#> #   xml_node_id <int>, xml_parent_node_id <int>, xml_depth <int>,
#> #   xml_source_path <chr>, xml_namespace_uri <chr>, xml_key_column <chr>,
#> #   xml_key_value <chr>, xml_namespaces <chr>, orders__attr_generated <chr>,
#> #   order__attr_id <chr>, order__attr_status <chr>,
#> #   order__customer__name <chr>, order__customer__postal_code <chr>,
#> #   item__attr_sku <chr>, item__attr_quantity <int>, item__description <chr>, …
```

The analyst table retains universal `xml_*` provenance/entity columns.
For production extraction across a family of documents, prefer an
explicit profile once the intended structure is understood.
