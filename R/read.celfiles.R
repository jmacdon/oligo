smartReadCEL <- function(filenames, sampleNames, headdetails,
                         verbose=TRUE){

  nr <- prod(headdetails[[2]])
  dns <- list(as.character(1:nr), sampleNames)
  
  if (isPackageLoaded("ff")){
    tmpExprs <- createFF("intensities-", dim=c(nr, length(filenames)))
    intensityFile <- filename(tmpExprs)
    samplesByNode <- splitIndicesByNode(1:length(filenames))
    datetime <- ocLapply(samplesByNode, oligoReadCels, headdetails,
                         filenames, tmpExprs, neededPkgs="oligo")
    datetime <- unlist(datetime)
  }else{
    intensityFile <- NA_character_
    tmpExprs <- .Call("read_abatch", filenames, FALSE, FALSE, FALSE,
                      headdetails[[1]], headdetails[[2]], verbose,
                      PACKAGE="affyio")
    datetime <- GetAffyTimeDateAsString(filenames)
  }
  dimnames(tmpExprs) <- dns
  rm(headdetails, dns)
  return(list(exprMatrix=tmpExprs, intensityFile=intensityFile, datetime=datetime))
}

oligoReadCels <- function(cols, headdetails, filenames, out){
  ## runs on the nodes
  if (length(cols) > 0){
    grpCols <- splitIndicesByLength(cols, ocSamples())
    dates <- vector("list", length(grpCols))
    open(out)
    i <- 1
    for (theCols in grpCols){
      out[, theCols] <- .Call("read_abatch", filenames[theCols], FALSE,
                              FALSE, FALSE, headdetails[[1]],
                              headdetails[[2]], FALSE, PACKAGE="affyio")
      dates[[i]] <- GetAffyTimeDateAsString(filenames[theCols])
      i <- i + 1
  }
    close(out)
    rm(grpCols, out)
    gc()
    return(unlist(dates))
  }
  TRUE
}

read.celfiles <- function( ..., filenames, pkgname, phenoData,
                          featureData, experimentData, protocolData,
                          notes, verbose=TRUE, sampleNames,
                          rm.mask=FALSE, rm.outliers=FALSE,
                          rm.extra=FALSE, checkType=TRUE){
  ##       add protocolData with scandate
  filenames <- getFilenames(filenames=filenames, ...)
  checkValidFilenames(filenames)
  if (checkType)
    stopifnot(checkChipTypes(filenames, verbose, "affymetrix",
                             TRUE))
  
  ## Read in the first Array details
  chiptype <- getCelChipType(filenames[1], TRUE)
  
  if (missing(pkgname))
    pkgname <- cleanPlatformName(chiptype)
  
  if (requireAnnotation(pkgname, verbose=verbose)){
    if (verbose)
      message("Platform design info loaded.")
  }else{
    stop("The annotation package, ", pkgname, ", could not be loaded.")
  }

  headdetails <- .Call("ReadHeader", as.character(filenames[1]),
                       PACKAGE="affyio")

  if (missing(sampleNames))
    sampleNames <- basename(filenames)

  results <- smartReadCEL(filenames, sampleNames, headdetails=headdetails)
  tmpExprs <- results[["exprMatrix"]]
  intensityFile <- results[["intensityFile"]]
  datetime <- results[["datetime"]]
  rm(results)

  arrayType <- kind(get(pkgname))
  theClass <- switch(arrayType,
                     generic="GenericFeatureSet",
                     tiling="TilingFeatureSet",
                     expression="ExpressionFeatureSet",
                     SNP="SnpFeatureSet",
                     SNPCNV="SnpCnvFeatureSet",
                     exon="ExonFeatureSet",
                     gene="GeneFeatureSet",
                     hta="HTAFeatureSet",
                     stop("Unknown array type: ", arrayType))
  
  out <- new(theClass)
  slot(out, "assayData") <- assayDataNew(exprs=tmpExprs)
  overwrite <- FALSE
  if (missing(phenoData)){
      phenoData <- basicPhData1(tmpExprs)
  }else{
      overwrite <- TRUE
      sns <- sampleNames(phenoData)
      vmd <- varMetadata(phenoData)
      if (!('channel' %in% colnames(vmd))){
          warning("'channel' automatically added to varMetadata in phenoData.")
          vmd$channel <- factor(rep("_ALL_", nrow(vmd)), levels=c("exprs", "_ALL_"))
          varMetadata(phenoData) <- vmd
      }
  }
  slot(out, "phenoData") <- phenoData
  if (overwrite)
      sampleNames(out) <- sns
  rm(phenoData)
  if (missing(featureData))
      featureData <- basicAnnotatedDataFrame(tmpExprs, TRUE)
  slot(out, "featureData") <- featureData
  rm(featureData)
  if (missing(protocolData))
      protocolData <- basicPData(tmpExprs, filenames, datetime)
  if (overwrite)
      sampleNames(protocolData) <- sns
  slot(out, "protocolData") <- protocolData
  rm(protocolData)
  slot(out, "manufacturer") <- "Affymetrix"
  slot(out, "annotation") <- pkgname
  slot(out, "intensityFile") <- intensityFile
  if (validObject(out)){
    return(out)
  }else{
    stop("Resulting object is invalid.")
  }

}

## TilingFeatureSet2

read.celfiles2 <- function(channel1, channel2, pkgname, phenoData,
                           featureData, experimentData, protocolData, notes,
                           verbose=TRUE, sampleNames, rm.mask=FALSE,
                           rm.outliers=FALSE, rm.extra=FALSE,
                           checkType=TRUE){

  filenames <- c(channel1, channel2)
  checkValidFilenames(filenames)
  if (checkType) stopifnot(checkChipTypes(filenames, verbose, "affymetrix", TRUE))
  
  ## Read in the first Array details
  headdetails <- readCelHeader(filenames[1])
  chiptype <- headdetails[["chiptype"]]
  
  if (missing(pkgname))
    pkgname <- cleanPlatformName(chiptype)
  
  if (requireAnnotation(pkgname, verbose=verbose)){
    if (verbose)
      message("Platform design info loaded.")
  }else{
    stop("Must install the ", pkgname, " package.")
  }
  
  arrayType <- kind(get(pkgname))
  if (missing(sampleNames))
    sampleNames <- basename(channel1)

  results <- smartReadCEL(channel1, sampleNames, headdetails=headdetails)
  channel1Intensities <- results[["exprMatrix"]]
  intensityFile1 <- results[["intensityFile"]]
  datetime1 <- results[["datetime"]]
  rm(results)
  results <- smartReadCEL(channel2, sampleNames, headdetails=headdetails)
  channel2Intensities <- results[["exprMatrix"]]
  intensityFile2 <- results[["intensityFile"]]
  datetime2 <- results[["datetime"]]
  rm(results, headdetails)

  theClass <- "TilingFeatureSet"
  out <- new(theClass)
  slot(out, "assayData") <- assayDataNew(channel1=channel1Intensities,
                                         channel2=channel2Intensities)
  overwrite <- FALSE
  if (missing(phenoData)){
      phenoData <- basicPhData2(channel1Intensities,
                                channel2Intensities)
  }else{
      overwrite <- TRUE
      sns <- sampleNames(phenoData)
  }
  slot(out, "phenoData") <- phenoData
  if (overwrite)
      sampleNames(out) <- sns
  rm(phenoData)
  if (missing(featureData))
      featureData <- basicAnnotatedDataFrame(channel1Intensities, TRUE)
  slot(out, "featureData") <- featureData
  rm(featureData)
  if (missing(protocolData))
    protocolData <- basicPData2(channel1Intensities,
                                channel2Intensities,
                                channel1, channel2,
                                datetime1, datetime2)
  if (overwrite)
      sampleNames(protocolData) <- sns
  slot(out, "protocolData") <- protocolData
  rm(protocolData)
  slot(out, "manufacturer") <- "Affymetrix"
  slot(out, "annotation") <- pkgname
  slot(out, "intensityFile") <- c(intensityFile1, intensityFile2)
  if (validObject(out)){
    return(out)
  }else{
    stop("Resulting object is invalid.")
  }
}

## FOR AXIOM
read.mc.celfiles <- function( ..., filenames, pkgname, phenoData,
                             featureData, experimentData, protocolData,
                             notes, verbose=TRUE, sampleNames,
                             rm.mask=FALSE, rm.outliers=FALSE,
                             rm.extra=FALSE, checkType=TRUE){
    ## Very first implementation
    ## not memory efficient
    
    ## add protocolData with scandate
    filenames <- getFilenames(filenames=filenames, ...)
    checkValidFilenames(filenames)

    ## check type...
    ## original fails because we cant read header yet
    ## if (checkType)
    ##     stopifnot(checkChipTypes(filenames, verbose, "affymetrix",
    ##                              TRUE))

    ## read all files:
    allCels <- lapply(filenames, affyio::read.celfile,
                      intensity.means.only=TRUE)

    if (checkType){
        chiptype <- unique(sapply(allCels, function(x) x[['HEADER']][['cdfName']]))
        stopifnot(length(chiptype) == 1)
    }
    
    ## Read in the first Array details
    ## chiptype <- getCelChipType(filenames[1], TRUE)
    
    if (missing(pkgname))
        pkgname <- cleanPlatformName(chiptype)
    
    if (requireAnnotation(pkgname, verbose=verbose)){
        if (verbose)
            message("Platform design info loaded.")
    }else{
        stop("The annotation package, ", pkgname, ", could not be loaded.")
    }
    
    ## headdetails <- .Call("ReadHeader", as.character(filenames[1]),
    ##                      PACKAGE="affyio")
    
    if (missing(sampleNames))
        sampleNames <- basename(filenames)
    
    ## results <- smartReadCEL(filenames, sampleNames, headdetails=headdetails)
    ## tmpExprs <- results[["exprMatrix"]]
    ## intensityFile <- results[["intensityFile"]]
    intensityFile1 <- ""
    intensityFile2 <- ""
    ## datetime <- results[["datetime"]]
    ## rm(results)
    channel1 <- sapply(allCels, function(x) x[['INTENSITY']][[1]][['MEAN']])
    channel2 <- sapply(allCels, function(x) x[['INTENSITY']][[2]][['MEAN']])
    datetime <- sapply(allCels, function(x) x[['HEADER']][['DatHeader']])
    rm(allCels)
    colnames(channel1) <- colnames(channel2) <- sampleNames
    rownames(channel1) <- rownames(channel2) <- 1:nrow(channel1)
    
    arrayType <- kind(get(pkgname))
    theClass <- switch(arrayType,
                       generic="GenericFeatureSet",
                       tiling="TilingFeatureSet",
                       expression="ExpressionFeatureSet",
                       SNP="SnpFeatureSet",
                       SNPCNV="SnpCnvFeatureSet",
                       exon="ExonFeatureSet",
                       gene="GeneFeatureSet",
                       stop("Unknown array type: ", arrayType))
  
    out <- new(theClass)
    slot(out, "assayData") <- assayDataNew(channel1=channel1, channel2=channel2)



    if (missing(phenoData))
        phenoData <- basicPhData2(channel1, channel2)
    slot(out, "phenoData") <- phenoData
    rm(phenoData)
    if (missing(featureData))
        featureData <- basicAnnotatedDataFrame(channel1, TRUE)
    slot(out, "featureData") <- featureData
    rm(featureData)
    if (missing(protocolData))
        protocolData <- basicPData2(channel1, channel2, filenames,
                                    filenames, datetime, datetime)
    slot(out, "protocolData") <- protocolData
    rm(protocolData)
    slot(out, "manufacturer") <- "Affymetrix"
    slot(out, "annotation") <- pkgname
    slot(out, "intensityFile") <- c(intensityFile1, intensityFile2)
    if (validObject(out)){
        return(out)
    }else{
        stop("Resulting object is invalid.")
    }
}
