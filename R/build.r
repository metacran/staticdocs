#' Build complete static documentation for a package.
#'
#' Currently, knitr builds documentation for:
#'
#' \itemize{
#'   \item Rd files.  Files
#'   \item Demos. Must be listed in \file{demos/00index}.
#'   \item Vignettes.
#' }
#'
#' @param package path to source version of package.  See
#'   \code{\link[devtools]{as.package}} for details on how paths and package
#'   names are resolved.
#' @param base_path root directory in which to create documentation
#' @param examples include examples or not?  Examples are particularly
#'   slow to render because all code must be run, so turning them off makes
#'   it easier to tweak templates etc.
#' @export
#' @import stringr
#' @importFrom devtools load_all
#' @aliases staticdocs-package
build_package <- function(package, base_path = NULL, examples = NULL) {
  load_all(package)
  
  package <- package_info(package, base_path, examples)
  if (!file.exists(package$base_path)) dir.create(package$base_path)
  copy_bootstrap(base_path)

  package$topics <- build_topics(package)
  package$vignettes <- build_vignettes(package)
  package$demos <- build_demos(package)
  package$readme <- readme(package)
  
  build_index(package)
  
  if (interactive()) {
    browseURL(normalizePath(file.path(base_path, "index.html")))
  }
  invisible(TRUE)
}

build_index <- function(package) {
  out <- file.path(package$base_path, "index.html")
  message("Generating index.html")

  topic_index <- package$topics[package$topics$in_index, , drop = FALSE]
  package$topic_index <- rows_list(topic_index)
  
  render_template("index", package, out)
}

#' Generate all topic pages for a package.
#'
#' @export
#' @inheritParams build_package
#' @param package_info A list containing information about the package,
#'   as generated by \code{\link{package_info}}
#' @keywords internal
build_topics <- function(package) {

  # for each file, find name of one topic
  index <- package$rd_index
  topics <- index$alias[!duplicated(index$file_in)]
  files_in <- index$file_in[!duplicated(index$file_in)]
  files_out <- index$file_out[!duplicated(index$file_in)]
  paths <- file.path(package$base_path, files_out)

  # create columns for extra topic info
  index$title <- ""
  index$in_index <- TRUE
  
  for (i in seq_along(topics)) {
    message("Generating ", basename(paths[[i]]))
    
    rd <- package$rd[[files_in[i]]]
    html <- to_html(rd, 
      env = new.env(parent = globalenv()), 
      topic = str_replace(basename(paths[[i]]), "\\.html$", ""),
      package = package)

    html$package <- package
    render_template("topic", html, paths[[i]])
    graphics.off()

    all_topics <- index$file_out == files_out[i]
    if ("internal" %in% html$keywords) {
      index$in_index[all_topics] <- FALSE
    }
    index$title[all_topics] <- html$title
  }

  index
}

#' @importFrom markdown markdownToHTML
readme <- function(package) {
  path <- file.path(package$path, "README.md")
  if (!file.exists(path)) return()
  
  (markdownToHTML(path))
}

copy_bootstrap <- function(base_path) {
  bootstrap <- file.path(inst_path(), "bootstrap")
  file.copy(dir(bootstrap, full.names = TRUE), base_path, recursive = TRUE)
}


#' List all package vignettes.
#'
#' Copies all vignettes and returns data structure suitable for use with
#' whisker templates.
#'
#' @keywords internal
#' @inheritParams build_package
#' @return a list, with one element for each vignette containing the vignette
#'   title and file name.
build_vignettes <- function(package) {  
  # Locate source and built versions of vignettes
  path <- dir(file.path(package$path, c("inst/doc", "vignettes")), ".Rnw", 
    full.names = TRUE)
  if (length(path) == 0) return()
  
  message("Building vignettes")
  buildVignettes(dir = package$path)
  
  message("Copying vignettes")
  src <- str_replace(path, "\\.Rnw$", ".pdf")
  filename <- basename(src)
  dest <- file.path(package$base_path, "vignettes")

  if (!file.exists(dest)) dir.create(dest)
  file.copy(src, file.path(dest, filename))  

  # Extract titles
  title <- vapply(path, FUN.VALUE = character(1), function(x) {
    contents <- str_c(readLines(x), collapse = "\n")
    str_match(contents, "\\\\VignetteIndexEntry\\{(.*?)\\}")[2]
  })  
  
  unname(apply(cbind(filename, title), 1, as.list))
}


build_demos <- function(package, index) {
  demo_dir <- file.path(package$path, "demo")
  if (!file.exists(demo_dir)) return()
  
  message("Rendering demos")
  demos <- readLines(file.path(demo_dir, "00Index"))
  
  pieces <- str_split_fixed(demos, "\\s+", 2)
  in_path <- str_c(pieces[, 1], ".r")
  out_path <- str_c("demo-", pieces[,1], ".html")
  title <- pieces[, 2]
  
  for(i in seq_along(title)) {
    demo_code <- readLines(file.path(demo_dir, in_path[i]))
    demo_expr <- evaluate(demo_code, new.env(parent = globalenv()))

    package$demo <- replay_html(demo_expr,
      package = package, 
      name = str_c(pieces[i], "-"))
    package$title <- title[i]
    render_template("demo", package, 
      file.path(package$base_path, out_path[i]))
  }
  
  unname(apply(cbind(out_path, title), 1, as.list))
}
