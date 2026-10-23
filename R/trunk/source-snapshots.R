# Public-source captures. No catalog, institution or Shiny decisions live here.

source_sha256 <- function(bytes) digest::digest(bytes, algo = "sha256", serialize = FALSE)

source_json_bytes <- function(value) {
  charToRaw(enc2utf8(as.character(jsonlite::toJSON(value, auto_unbox = TRUE,
    null = "null", na = "null", pretty = TRUE, digits = NA))))
}

write_source_json <- function(value, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  temporary <- paste0(path, ".", Sys.getpid(), ".tmp")
  writeBin(source_json_bytes(value), temporary)
  if (!file.rename(temporary, path)) stop("[source-snapshots.R] Cannot publish ", path)
  invisible(path)
}

read_source_json <- function(path) jsonlite::fromJSON(path, simplifyVector = FALSE)

# Resolve an RFC 6901 pointer without guessing missing fields or array indexes.
source_json_pointer <- function(document, pointer) {
  if (identical(pointer, "")) return(document)
  if (length(pointer) != 1L || is.na(pointer) || !startsWith(pointer, "/")) {
    stop("[source-snapshots.R] Invalid JSON pointer")
  }
  keys <- head(strsplit(paste0(substring(pointer, 2L), "/END"), "/", fixed = TRUE)[[1]], -1L)
  if (any(grepl("~(?![01])", keys, perl = TRUE))) stop("[source-snapshots.R] Invalid JSON pointer escape")
  for (key in keys) {
    key <- gsub("~1", "/", key, fixed = TRUE)
    key <- gsub("~0", "~", key, fixed = TRUE)
    if (!is.list(document)) stop("[source-snapshots.R] JSON pointer does not resolve: ", pointer)
    if (is.null(names(document))) {
      if (!grepl("^(0|[1-9][0-9]*)$", key) || as.numeric(key) >= length(document)) {
        stop("[source-snapshots.R] JSON array pointer does not resolve: ", pointer)
      }
      document <- document[[as.integer(key) + 1L]]
    } else {
      if (!key %in% names(document)) stop("[source-snapshots.R] JSON field pointer does not resolve: ", pointer)
      document <- document[[key]]
    }
  }
  document
}

#' Fetch one public document; HTTP and JSON errors are never empty datasets
fetch_public_source <- function(url) {
  if (length(url) != 1L || !grepl("^https://", url)) {
    stop("[source-snapshots.R] Public sources require an HTTPS URL")
  }
  handle <- curl::new_handle(timeout = 60, connecttimeout = 20,
    useragent = "CEDAR catalog source scanner", accept_encoding = "")
  response <- curl::curl_fetch_memory(url, handle = handle)
  if (response$status_code != 200L) {
    stop("[source-snapshots.R] HTTP ", response$status_code, " for ", url)
  }
  headers <- curl::parse_headers_list(response$headers)
  list(body = response$content, final_url = response$url,
    status_code = response$status_code, content_type = response$type,
    etag = if (is.null(headers$etag)) "" else headers$etag,
    last_modified = if (is.null(headers[["last-modified"]])) "" else headers[["last-modified"]])
}

#' Save exact decoded response bytes and a receipt. Existing blobs are immutable.
capture_public_source <- function(url, directory, kind, key, fetch = fetch_public_source,
                                  document_format = "json") {
  response <- fetch(url)
  if (!is.raw(response$body) || response$status_code != 200L || !length(response$body)) {
    stop("[source-snapshots.R] Invalid source response for ", url)
  }
  if (document_format == "json") jsonlite::fromJSON(rawToChar(response$body), simplifyVector = FALSE)
  hash <- source_sha256(response$body)
  relative <- paste0("sources/", hash, ".body")
  path <- file.path(directory, relative)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  if (file.exists(path)) {
    if (!identical(source_sha256(readBin(path, "raw", n = file.info(path)$size)), hash)) {
      stop("[source-snapshots.R] Existing source blob is corrupt: ", path)
    }
  } else writeBin(response$body, path)
  list(kind = kind, key = key, url = url, final_url = response$final_url,
    fetched_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    status_code = response$status_code, content_type = response$content_type,
    etag = response$etag, last_modified = response$last_modified,
    sha256 = hash, file = relative)
}

#' Verify a receipt before reading its captured bytes, including on resume
read_captured_source <- function(receipt, directory, json = TRUE) {
  if (!grepl("^sources/[a-f0-9]{64}\\.body$", receipt$file) ||
      !identical(receipt$file, paste0("sources/", receipt$sha256, ".body"))) {
    stop("[source-snapshots.R] Invalid source receipt path")
  }
  path <- file.path(directory, receipt$file)
  if (!file.exists(path)) stop("[source-snapshots.R] Missing source blob: ", path)
  bytes <- readBin(path, "raw", n = file.info(path)$size)
  if (!identical(source_sha256(bytes), receipt$sha256)) {
    stop("[source-snapshots.R] Source hash mismatch: ", path)
  }
  if (json) jsonlite::fromJSON(rawToChar(bytes), simplifyVector = FALSE) else rawToChar(bytes)
}
