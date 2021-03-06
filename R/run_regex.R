#' Extract matched groups from regexp
#'
#' @param text Text to search
#' @param pattern regexp
#' @inheritParams base::regexec
#' @export
run_regex <- function(
  text,
  pattern,
  ignore.case = FALSE,
  perl = FALSE,
  fixed = FALSE,
  useBytes = FALSE,
  invert = FALSE
) {
  # Use regex to get matches by group, gives start index and length
  m <- regexec(pattern, text, ignore.case, perl, fixed, useBytes)
  # Convert to start/end index
  x <- purrr::map(m, function(mi) {
    list(
      'idx' = purrr::map2(mi, attr(mi, "match.length"),
                          ~ if(.x[1] != -1) c(.x, .x + .y - 1L)))
  })
  # Store text and original regexc result with same hierarchy
  y <- purrr::map(text, ~ list(text = .))
  z <- purrr::map(regmatches(text, m), ~ list(m = .))
  # Zip text, indexes and regexc match object lists
  purrr::map(seq_along(x), ~ list(text = y[[.]][[1]], idx = x[[.]][[1]], m = z[[.]][[1]]))
}

wrap_result <- function(x, escape = FALSE) {
  if (is.null(x$idx[[1]])) return(if (escape) escape_html(x$text) else x$text)
  text <- x$text
  idx <- x$idx
  len_idx <- length(idx)
  inserts <- data.frame(
    i = 1:len_idx - 1,
    start = purrr::map_int(idx, ~ .[1]),
    end = purrr::map_int(idx, ~ .[2]) + 1
  ) %>%
    mutate(
      class = sprintf("group g%02d", .data$i),
      pad = 0
    )
  for (j in seq_len(nrow(inserts))) {
    if (inserts$i[j] == 0) next
    overlap <- filter(
      inserts[1:(j-1), ],
      .data$i != 0,
      .data$start <= !!inserts$start[j] & .data$end >= !!inserts$end[j])
    inserts[j, 'pad'] <- inserts$pad[j] + nrow(overlap)
  }
  inserts <- inserts %>%
    tidyr::gather(type, loc, start:end) %>%
    mutate(
      class = ifelse(.data$pad > 0, sprintf("%s pad%02d", .data$class, .data$pad), .data$class),
      insert = ifelse(.data$type == 'start', sprintf('<span class="%s">', .data$class), "</span>")
    ) %>%
    group_by(.data$loc, .data$type) %>%
    summarize(insert = paste(.data$insert, collapse = ''))

  # inserts now gives html (span open and close) to insert and loc
  # first split text at inserts$loc locations,
  # then recombine by zipping with inserts$insert text
  # start at 0, unless there's a hit on first character
  # end at nchar(text) + 1 because window is idx[k] to idx[k+1]-1
  idx_split <- c(0 - (inserts$loc[1] == 0), inserts$loc)
  if (!(nchar(text) + 1) %in% idx_split)
    idx_split <- c(idx_split, nchar(text) + 1)
  text_split <- c()
  for (k in seq_along(idx_split[-1])) {
    text_split <- c(text_split, substr(text, idx_split[k], idx_split[k+1] - 1))
  }
  out <- c()
  for (j in seq_along(text_split)) {
    out <- c(
      out,
      ifelse(escape, escape_html(text_split[j]), text_split[j]),
      if (!is.na(inserts$insert[j])) inserts$insert[j]
    )
  }
  paste(out, collapse = '')
}

wrap_regex <- function(pattern, escape = TRUE, exact = TRUE) {
  stopifnot(length(pattern) == 1)
  if(escape) pattern <- escape_html(pattern)
  r_open_parens <- "(?<![\\\\])\\("
  x <- strsplit(pattern, r_open_parens, perl = TRUE)[[1]]
  first <- x[1]
  x <- x[-1]
  if (length(x)) {
    x <- paste0(
      '<span class="g', sprintf("%02d", seq_along(x)), '">(',
      x,
      collapse = ""
    )
    x <- gsub("(?<![\\\\])\\)", ")</span>", x, perl = TRUE)
  }
  if (exact) x <- escape_backslash(x)
  paste0(first, x)
}

#' View grouped regex results
#'
#' @param text Text to search
#' @param pattern Regex pattern to look for
#' @param render Render results to an HTML doc and open in RStudio viewer?
#' @param escape Escape HTML-related characters in `text`?
#' @param knitr Print into knitr doc? If `TRUE`, marks text as `asis_output` and
#'   sets `render = FALSE` and `escape = TRUE`.
#' @param exact Should regex be displayed as entered by the user into R console
#'   or source (default)? When `TRUE`, regex is displayed with the double `\\`
#'   required for escaping backslashes in R. When `FALSE`, regex is displayed
#'   as interpreted by the regex engine (i.e. double `\\` as a single `\`).
#' @param ... Passed to [run_regex]
#' @export
view_regex <- function(
  text,
  pattern,
  ...,
  render = TRUE,
  escape = render,
  knitr = FALSE,
  exact = escape
) {
  if (knitr) {
    render <- FALSE
    escape <- TRUE
  }
  res <- run_regex(text, pattern, ...)
  res <- purrr::map_chr(res, wrap_result, escape = escape)
  res <- purrr::map_chr(res, function(resi) {
    result_pad <- ""
    if (grepl("pad\\d{2}", resi)) {
      max_pad <- max(stringr::str_extract_all(resi, "pad\\d{2}")[[1]])
      max_pad_level <- as.integer(stringr::str_extract(max_pad, "\\d{2}"))
      if (max_pad_level - 3 > 0) {
        result_pad <- sprintf("pad%02d", max_pad_level - 3)
      }
    }
    paste("<p class='results", result_pad, "'>", resi, "</p>")
  })
  res <- paste(res, collapse = "")
  if (!nchar(pattern)) res <- paste("<p class='results'>", text, "</p>")
  if (knitr) return(knitr::asis_output(res))
  if (!render) return(res)
  head <- c(
    "---", "pagetitle: View Regex", "---",
    "<h5 style = 'font-size: 1.1em'>Regex</h5>",
    "<p><pre style = 'font-size: 1.25em;'>", wrap_regex(pattern, escape, exact), "</pre></p>",
    "<h5 style = 'font-size: 1.1em'>Results</h5>"
  )
  res <- c(head, res)
  tmp <- tempfile(fileext = ".Rmd")
  cat(res, file = tmp, sep = "\n")
  tmp_html <- suppressWarnings(
    rmarkdown::render(
      tmp,
      output_format = rmarkdown::html_document(css = system.file('style.css', package='regexhelp'), theme = NULL),
      quiet = TRUE
  ))
  rstudioapi::viewer(tmp_html)
}
