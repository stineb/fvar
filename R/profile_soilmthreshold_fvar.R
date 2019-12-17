profile_soilmthreshold_fvar <- function(df_train,
                                        settings,
                                        weights = NA,
                                        len = 10){
  
  ## profile threshold
  thresh_seq <- seq(from = 0, to = 1, length.out = len+2)
  thresh_seq <- thresh_seq[-1]
  thresh_seq <- thresh_seq[-length(thresh_seq)]
  
  df_eval <- purrr::map(
    as.list(thresh_seq),
    ~profile_soilmthreshold_fvar_bythreshold(
      .,
      df_train = df_train,
      settings = settings,
      weights = weights
      )
    ) %>% 
    bind_rows()
  
  return(df_eval)
}

profile_soilmthreshold_fvar_bythreshold <- function(threshold,
                                                    df_train,
                                                    settings,
                                                    weights = NA){
  
  ## Train/predict
  df_nn <- train_predict_fvar( 
    df_train,
    settings,
    soilm_threshold    = threshold, 
    weights            = NA,
  )
  
  ## Performance evaluation
  df_eval <- test_performance_fvar(df_nn)$df_metrics %>% 
    dplyr::mutate(threshold = threshold)
  
  return(df_eval)
}