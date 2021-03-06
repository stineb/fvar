#' Aligns data by events
#'
#' Uses a vectory specifying whether data falls into an event to reshape data, aligning by the onset of the event
#' 
#' @param df A data frame containing all data continuously along time. The data frame must contain one column of type logical
#' named \code{"isevent"}, specifying whether respective dates satisfy a user-defined condition that is used to define events. 
#' Events are determined by the function based on consecutive dates, where this condition is satisfied (minimum length for 
#' defining an event is given by \code{leng_threshold}).
#' @param dovars A vector of character strings specifying which columns of \code{df} to re-arrange.
#' @param before An integer specifying the number of days before the event onset to be retained in re-arranged data 
#' @param after An integer specifying the number of days after the event onset to be retained in re-arranged data 
#' @param do_norm A logical specifying whether re-arranged data is to be normalised with respect to its value before the drought onset

#'
#' @return An aligned data frame
#' @export
#'
#' @examples df_alg <- align_events( df, before=30, after=300 )
#' 
align_events <- function( df, dovars, leng_threshold, before, after, nbins, do_norm=FALSE ){

  require( dplyr )
  require( tidyr )

  if (!("isevent" %in% names(df))){
    rlang::abort("align_events(): Column named isevent is missing in data frame df.")
  }


  ## Bins for different variables XXX a bit weird with default values
  bins  <- seq( from=-before, to=after, by=(after+before)/nbins )

  ## merge df_isevent into df
  df <- df %>% mutate( idx_df = 1:n() )

  ##--------------------------------------------------------
  ## Identify events ()
  ##--------------------------------------------------------
  events <- get_consecutive( 
              df$isevent, 
              leng_threshold = leng_threshold, 
              do_merge       = FALSE
              )

  ##--------------------------------------------------------
  ## Re-arrange data, aligning by beginning of events
  ## Creates data frame where not all rows are retained from df
  ## and columns added for 'dday' (number of day relative to onset of event)
  ## and 'iinst' number of event to which row belongs.
  ##--------------------------------------------------------
  if (nrow(events)>1){

    df_dday <- tibble()
    for ( iinst in 1:nrow(events) ){
      after_inst <- min( after, events$len[iinst] )
      dday <- seq( from=-before, to=after_inst, by=1 )
      idxs <- dday + events$idx_start[iinst]
      drophead <- which( idxs < 1 )
      if (length(drophead)>0){
        idxs <- idxs[ -drophead ]
        dday <- dday[ -drophead ]
      }
      addrows <- df %>% slice( idxs ) %>% mutate( dday=dday, inst=iinst )
      df_dday <- df_dday %>% bind_rows( addrows )              
    }

    ##--------------------------------------------------------
    ## Normalise re-arranged data relative to a certain bin's median for each site
    ##--------------------------------------------------------
    if (do_norm){
      ## add column for bin
      df_dday <- df_dday %>% mutate( inbin  = cut( as.numeric(dday), breaks = bins ) )
        
      ## Normalise by median value in dday-bin before drought onset ("zero-bin")
      ## Get median in zero-bin
      sdovars  <- paste0("s",  dovars)
      dsdovars <- paste0("ds", dovars)
      
      # ## Add median in zero-bin (dsdovars), separate for each site, aggregated across instances (drought events)
      # df_dday <- df_dday %>% group_by( site, inbin ) %>%
      #   summarise_at( vars(one_of(sdovars)), funs(median( ., na.rm=TRUE )) ) %>%
      #   filter( !is.na(inbin) ) %>% 
      #   filter( grepl(",0]", inbin) ) %>% 
      #   setNames( c( "site", "inbin", paste0("d", sdovars) ) ) %>% 
      #   select(-inbin) %>% 
      #   right_join(df_dday, by="site") %>% 
      #   ungroup()
      
      norm <- df_dday %>% group_by( site, inbin ) %>%
        summarise_at( vars(one_of(sdovars)), funs(median( ., na.rm=TRUE )) ) %>%
        filter( !is.na(inbin) ) %>% 
        filter( grepl(",0]", inbin) ) %>% 
        setNames( c( "site", "inbin", paste0("d", sdovars) ) ) %>% 
        select(-inbin)
      
      df_dday <- df_dday %>% 
        left_join(norm, by="site") %>% 
        ungroup()
      
      ## Divide by median in zero-bin
      get_dsdovar <- function(df, sdovar){
        dsdovar <- paste0("d", sdovar)
        df[[dsdovar]] <- df[[sdovar]] / df[[dsdovar]]
        return(select(df, dsdovar))
      }
      df_dday <- purrr::map_dfc(as.list(sdovars), ~get_dsdovar(df_dday, .)) %>% 
        bind_cols( select(df_dday, -one_of(dsdovars)), .)
      
    } else {
      sdovars <- c()
      dsdovars <- c()
    }
    
    ##--------------------------------------------------------
    ## Aggregate accross events, by site
    ##--------------------------------------------------------
    df_dday_agg_inst <- df_dday %>%  
      group_by( site, dday ) %>% 
      summarise_at( 
        vars(one_of(dovars, sdovars, dsdovars)), 
        list( ~median( ., na.rm=TRUE), ~q33( ., na.rm=TRUE), ~q66( ., na.rm=TRUE) ) )
    
    ##--------------------------------------------------------
    ## Aggregate accross events and sites
    ##--------------------------------------------------------
    df_dday_agg_inst_site <- df_dday %>%  
      group_by( dday ) %>% 
      summarise_at( 
        vars(one_of(dovars, sdovars, dsdovars)), 
        list( ~median( ., na.rm=TRUE), ~q33( ., na.rm=TRUE), ~q66( ., na.rm=TRUE) ) )

  } else {

    df_dday_agg_inst      <- NULL
    df_dday_agg_inst_site <- NULL

  }

  out <- list( 
    df_dday = df_dday, 
    df_dday_agg_inst = df_dday_agg_inst, 
    df_dday_agg_inst_site = df_dday_agg_inst_site,
    bins = bins,
    norm = norm
    )
  return( out )

}


get_consecutive <- function( dry, leng_threshold=5, anom=NULL, do_merge=FALSE ){
  ##------------------------------------
  ## Returns a dataframe that contains information about events (starting index and length) 
  ## of consecutive conditions (TRUE) in a boolean vector ('dry' - naming is a legacy).
  ##------------------------------------

  ## replace NAs with FALSE (no drought). This is needed because of NAs at head or tail
  dry[ which(is.na(dry)) ] <- FALSE

  ## identifies periods where 'dry' true for consecutive days of length>leng_threshold and 
  ## creates data frame holding each instance's info: start of drought by index in 'dry' and length (number of days thereafter)
  instances <- data.frame( idx_start=c(), len=c() )
  consecutive_dry <- rep( NA, length( dry ) )
  ndry  <- 0
  ninst <- 0
  for ( idx in 1:length( dry ) ){
    if (dry[idx]){ 
      ndry <- ndry + 1 
    } else {
      if (ndry>=leng_threshold) { 
        ## create instance
        ninst <- ninst + 1
        addrow <- data.frame( idx_start=idx-(ndry), len=ndry )
        instances <- rbind( instances, addrow )
      }
      ndry <- 0
    }
    consecutive_dry[idx] <- ndry
  }
  if (ndry>leng_threshold){
    ## create a last instance if the last dry period extends to the end of the time series
    ninst <- ninst + 1
    addrow <- data.frame( idx_start=idx-(ndry), len=ndry )
    instances <- rbind( instances, addrow )
  }


  if (nrow(instances)>0){

    ## Get cumulative deficit per instance (deficit w.r.t. 1, where 'anom' is a vector with values 0-1)
    if (!is.null(anom)){
      instances$deficit <- rep( NA, nrow(instances) )
      for ( idx in 1:nrow(instances) ){
        instances$deficit[idx] <- sum( anom[ instances$idx_start[idx]:(instances$idx_start[idx]+instances$len[idx]-1) ] )
      }
    }

    ## merge events interrupted by short non-drought periods
    ## if in-between non-drought period is shorter than both of the drought periods
    ## before and after non-drought period
    if (do_merge){
      
      print("dimensions of instances before merging short periods")
      print(dim(instances))

      ninst_save <- nrow( instances ) + 1
      ninst      <- nrow( instances )

      while (ninst < ninst_save){

        ninst_save <- nrow( instances )

        instances_merged <- data.frame( idx_start=c(), len=c() )

        idx <- 0
        while (idx<(nrow(instances)-1)){
          idx <- idx + 1

          len_betweendrought <- instances$idx_start[idx+1] - (instances$idx_start[idx] + instances$len[idx] + 1)
          
          if (len_betweendrought<instances$len[idx] && len_betweendrought<instances$len[idx+1]){
            addrow <- data.frame( idx_start=instances$idx_start[idx], len=(instances$idx_start[idx+1] + instances$len[idx+1]) - instances$idx_start[idx] )
            instances_merged <- rbind( instances_merged, addrow )
            idx <- idx + 1
          } else {
            instances_merged <- rbind( instances_merged, instances[idx,] )
            if (idx==(nrow(instances)-1)){
              instances_merged <- rbind( instances_merged, instances[idx+1,] )
            }
          }
        }

        instances <- instances_merged    

        ninst <- nrow( instances )

        print( "dimensions of instances after merging short periods" )
        print( dim( instances ) )

      }

    }

  }

  return( instances )
}


q33 <- function( vec, ... ){
  quantile( vec, 0.33, ...)
}

q66 <- function( vec, ... ){
  quantile( vec, 0.66, ...)
}


  

