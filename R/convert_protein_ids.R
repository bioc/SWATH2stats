#' Establish connection to biomaRt database
#'
#' This function establishes a connection to a biomart database.
#'
#' @param species  The species of the protein identifiers in the term used by
#'   biomaRt (e.g. "hsapiens_gene_ensembl", "mmusculus_gene_ensembl",
#'   "drerio_gene_ensembl", etc.)
#' @param ensembl.path  Ensembl host to connect to. Default: www.ensembl.org
#' @param mart   The type of mart (e.g. "ENSEMBL_MART_ENSEMBL", etc.)
#' @param verbose print a summary of the ensembl connection.
#' @return Connection for performing biomart queries.
#' @author Peter Blattmann
#' @examples{
#'  data_table <- data.frame(Protein = c("Q01581", "P49327", "2/P63261/P60709"),
#'                           Abundance = c(100, 3390, 43423))
#'  mart <- convert_protein_ids(data_table)
#'  }
#' @importFrom biomaRt useMart listDatasets listMarts
#' @export
load_mart <- function(species, 
                      ensembl.path = "www.ensembl.org", 
                      mart, 
                      verbose = FALSE) {
    dataset.mart <- species
    ensembl.mart <- useMart(mart, dataset = dataset.mart, host = ensembl.path)

    list.datasets <- listDatasets(ensembl.mart)
    list.datasets[which(list.datasets == dataset.mart), "version"]
    list.marts <- listMarts(ensembl.mart, host = ensembl.path)
    list.marts[which(list.marts == mart), "version"]
    
    if (verbose) {
        sink(file = paste(Sys.Date(), species, "Ensembl_Version.txt", sep = "_"))
        writeLines(c(paste("Species:", species), 
                     paste("Host:", ensembl.path), 
                     paste("Date:", Sys.Date()), 
                     paste("Dataset:", list.datasets[which(list.datasets == dataset.mart), "version"]),
                     paste("Version:", list.marts[which(list.marts == mart), "version"])))
        sink()
        sink(type = "message")
    }
    return(ensembl.mart)
}

#' Adds gene symbols to a table
#' 
#' Gather gene symbols from biomart and add them to a data frame.
#'
#' @note Protein identifiers from shared peptides should be separated by a forward
#' slash. The host of archived ensembl databases can be introduced as well
#' (e.g. "dec2017.archive.ensembl.org")
#'
#' @param data_table A data frame or file name.
#' @param gene_ID_table A table to match gene identifiers against
#' @param column_name The column name where the original protein identifiers
#'   are present.
#' @param ID1 The type of the original protein identifiers
#'   (e.g. "uniprotswissprot", "ensembl_peptide_id").
#' @param ID2   The type of the converted protein identifiers
#'   (e.g. "hgnc_symbol", "mgi_symbol", "external_gene_name").
#' @param id.separator   Separator between protein identifiers of shared
#'   peptides.
#' @param copy_nonconverted  Option defining if the identifiers that cannot be
#'   converted should be copied.
#' @return Returns the data frame with an added column of the converted protein identifiers.
#' @author Peter Blattmann
#' @examples {
#'   gene_ID_table <- data.frame(uniprotswissprot = c("Q01581", "P49327", "P60709"), 
#'                               hgnc_symbol = c("HMGCS1", "FASN", "ACTB"))
#'   data_table <- data.frame(Protein = c("Q01581", "P49327", "2/P63261/P60709"), 
#'                            Abundance = c(100, 3390, 43423))
#'   add_genesymbol(data_table, gene_ID_table)
#'   }
#' @importFrom data.table fread
#' @importFrom biomaRt getBM
#' @importFrom utils write.table
#' @export
add_genesymbol <- function(data_table, 
                           gene_ID_table, 
                           column_name = "Protein", 
                           ID1 = "uniprotswissprot",
                           ID2 = "hgnc_symbol", 
                           id.separator = "/", 
                           copy_nonconverted = TRUE) {
    # remove column if it already exists
    if (ID2 %in% colnames(data_table)) {
        data_table[, ID2] <- NULL
    }
    gene_ID_table[, ID2] <- as.character(gene_ID_table[, ID2])
    data_table <- merge(data_table, gene_ID_table, by.x = column_name, 
                        by.y = ID1,all.x = TRUE, sort = FALSE)
    # annotate the shared peptides
    .ids <- which(is.na(data_table[, ID2]))
    .ids <- intersect(.ids, grep(id.separator, data_table[, column_name]))

    for (i in .ids) {
        .Protein <- as.character(data_table[i, column_name])
        .Protein.single <- unlist(strsplit(.Protein, id.separator))

        # remove number in front of shared peptides
        if (!is.na(suppressWarnings(as.numeric(.Protein.single[1]))) & 
            nchar(.Protein.single[1]) <= 3) {
            .Protein.single <- .Protein.single[-1]
        }
        .Protein.new <- .Protein
        for (k in .Protein.single[.Protein.single %in% gene_ID_table[, ID1]]) {
            .Protein.new <- gsub(k, gene_ID_table[gene_ID_table[, ID1] == k, ID2],
                .Protein.new)
        }
        data_table[data_table[, column_name] == .Protein, ID2] <- .Protein.new

        if (!copy_nonconverted) {
            for (k in .Protein.single[!(.Protein.single %in% gene_ID_table[, ID1])]) {
                .Protein.new <- gsub(paste(id.separator, k, sep = ""), "", .Protein.new)
                .Protein.new <- gsub(paste(k, id.separator, sep = ""), "", .Protein.new)
            }
            data_table[data_table[, column_name] == .Protein, ID2] <- .Protein.new
        }
    }

    # add non converted IDs
    non_converted <- (is.na(data_table[,ID2]) | data_table[,ID2] =="")
    if (sum(non_converted)) {
        non_converted_ids <- unique(data_table[non_converted,column_name])
        if (sum(non_converted) > 20) {
            message("The following ", sum(non_converted), 
                    " identifiers were not converted and will be copied (the first 20 are shown): ",
                    paste(non_converted_ids[seq_len(20)], collapse = ", "))
        } else {
            message("The following identifiers were not converted and will be copied: ",
                    paste(non_converted_ids, collapse = ", "))
        }
        if (copy_nonconverted) {
            for (i in which(non_converted)) {
                data_table[i, ID2] <- data_table[i, column_name]
            }
        }
    }

    # bring gene_symbol column in front
    data_table <- data_table[, c(ID2, colnames(data_table)[seq(length(colnames(data_table)) - 1)])]

    return(data_table)
}

#' Convert protein ids
#'
#' This function renames protein ids in a data frame or file
#'
#' @param data_table   A data frame or file name.
#' @param column_name  The column name where the original protein identifiers are present.
#' @param species  The species of the protein identifiers in the term used by
#'   biomaRt (e.g. "hsapiens_gene_ensembl", "mmusculus_gene_ensembl",
#'   "drerio_gene_ensembl", etc.)
#' @param host  Path of the biomaRt database (e.g. "www.ensembl.org",
#'   "dec2017.archive.ensembl.org").
#' @param mart  The type of mart (e.g. "ENSEMBL_MART_ENSEMBL", etc.)
#' @param ID1   The type of the original protein identifiers
#'   (e.g. "uniprotswissprot", "ensembl_peptide_id").
#' @param ID2   The type of the converted protein identifiers
#'   (e.g. "hgnc_symbol", "mgi_symbol", "external_gene_name").
#' @param id.separator   Separator between protein identifiers of shared
#'   peptides.
#' @param copy_nonconverted   Option defining if the identifiers that cannot be
#'   converted should be copied.
#' @param verbose   Option to write a file containing the version of the
#'   database used.
#' @return The data frame with an added column of the converted protein
#'   identifiers.
#' @note Protein identifiers from shared peptides should be separated by a
#'   forward slash. The host of archived ensembl databases can be introduced as
#'   well (e.g. "dec2017.archive.ensembl.org")
#' @author Peter Blattmann
#' @examples
#'  \dontrun{
#'   data_table <- data.frame(
#'        "Protein" = c("Q01581", "P49327", "2/P63261/P60709"),
#'        "Abundance" = c(100, 3390, 43423))
#'   convert_protein_ids(data_table)
#' }
#' @importFrom methods is
#' @export
convert_protein_ids <- function(data_table, 
                                column_name = "Protein", 
                                species = "hsapiens_gene_ensembl",
                                host = "https://www.ensembl.org", 
                                mart = "ENSEMBL_MART_ENSEMBL", 
                                ID1 = "uniprotswissprot",
                                ID2 = "hgnc_symbol", 
                                id.separator = "/", 
                                copy_nonconverted = TRUE, 
                                verbose = FALSE) {

    if (is(data_table, "data.frame")) {
        type <- "data.frame"
    } else {
        type <- "file"
        data_table <- data.frame(fread(file, sep = "\t", header = TRUE))
    }

    if (!(column_name %in% colnames(data_table))) {
        stop("Column name does not exist in data. ", paste(colnames(data_table),
            collapse = ", "))
    }

    # obtain Identifiers to map
    IDs <- unique(as.character(data_table[, column_name]))

    # separate non-proteotypic peptides
    IDs.np <- IDs[grep(id.separator, IDs)]
    IDs.np <- gsub("^[[:digit:]]+/", "", IDs.np)
    IDs.np <- unlist(strsplit(IDs.np, id.separator))

    # remove contaminant peptides
    IDs <- IDs[grep("^CONT_", IDs, invert = TRUE)]
    IDs.np <- IDs.np[grep("^CONT_", IDs.np, invert = TRUE)]

    IDs <- unique(c(IDs, IDs.np))
    length(IDs)

    organism.mart <- load_mart(species, host, mart)
    gene_ID_table <- getBM(attributes = c(ID2, ID1), filters = c(ID1), 
                           values = IDs, mart = organism.mart)

    n.ids <- table(gene_ID_table[, ID1])
    n.ids.multiple <- names(n.ids[n.ids > 1])
    for (i in n.ids.multiple) {
        new.id <- paste(gene_ID_table[gene_ID_table[, ID1] == i, ID2], 
                        collapse = id.separator)
        gene_ID_table <- gene_ID_table[gene_ID_table[, ID1] != i, ]
        new.id.df <- data.frame(uniprotswissprot = i, hgnc_symbol = new.id)
        colnames(new.id.df) <- c(ID1, ID2)
        gene_ID_table <- rbind(gene_ID_table, new.id.df)
    }

    data_table_output <- add_genesymbol(data_table, gene_ID_table, 
                                        column_name, ID1, ID2, 
                                        id.separator, copy_nonconverted)

    if (type == "file") {
        file.name <- gsub("\\..*", "", file)
        file.ext <- gsub(".*\\.", "", file)
        write.table(data_table_output, 
                    paste(file.name, "_annotated.", file.ext, sep = ""), 
                    quote = FALSE, row.names = FALSE, sep = "\t")
    }

    if (type == "data.frame") {
        data_table_output
    }
}
