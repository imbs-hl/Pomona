
#' Variable selection using Vita approach.
#'
#' This function calculates p-values based on the empirical null distribution from non-positive VIMs as
#' described in Janitza et al. (2015). Note that this function uses the \code{importance_pvalues} function in the R package
#' \code{\link[ranger]{ranger}}.
#'
#' @inheritParams wrapper.rf
#' @param p.t threshold for p-values (all variables with a p-value = 0  or < p.t will be selected)
#' @param fdr.adj If TRUE, methods of Benjamini, Hochberg, and Yekutieli is applied to control the false discovery rate.
#' @param holdout If TRUE, the holdout variable importance is calculated.
#' @param ... additional parameters passed to \code{getImp}
#'
#' @return List with the following components:
#'   \itemize{
#'   \item \code{info} data.frame
#'   with information for each variable
#'   \itemize{
#'   \item vim = variable importance (VIM)
#'   \item CI_lower = lower confidence interval boundary
#'   \item CI_upper = upper confidence interval boundary
#'   \item pvalue = empirical p-value
#'   \item selected = variable has been selected
#'   }
#'   \item \code{var} vector of selected variables
#'   }
#'  @references
#'  Janitza, S., Celik, E. & Boulesteix, A.-L., (2015). A computationally fast variable importance test for random forest for high dimensional data, Technical Report 185, University of Munich, https://epub.ub.uni-muenchen.de/25587.
#'  Benjamini, Y., and Yekutieli, D. (2001). The control of the false discovery rate in multiple testing under dependency. Annals of Statistics, 29, 1165–1188. doi: 10.1214/aos/1013699998.
#'  @examples
#' # simulate toy data set
#' data = simulation.data.cor(no.samples = 100, group.size = rep(10, 6), no.var.total = 500)
#'
#' # select variables
#' res = var.sel.vita(x = data[, -1], y = data[, 1], p.t = 0.05)
#' res$var
#'
#' @export

var.sel.vita <- function(x, y, p.t = 0.05,
                         fdr.adj = TRUE,
                         ntree = 500,
                         mtry.prop = 0.2,
                         nodesize.prop = 0.1,
                         no.threads = 1,
                         method = "ranger",
                         type = "regression",
                         importance = "impurity_corrected",
                         replace = TRUE,
                         sample.fraction = ifelse(replace, 1, 0.632),
                         holdout = FALSE,
                         ...) {

  # ## train holdout RFs
  # res.holdout = holdout.rf(x = x, y = y,
  #                          ntree = ntree,
  #                          mtry.prop = mtry.prop,
  #                          nodesize.prop = nodesize.prop,
  #                          no.threads = no.threads,
  #                          type = type,
  #                          importance = importance)

  ## Train impurity corrected RFs
  # modified version of getImpRfRaw function to enable user defined mtry
  # values
  get_imp_ranger <- function(x, y, ...){
    x <- data.frame(x)
    imp.rf <- wrapper.rf(x = x,
                      y = y,
                      ...)
    return(imp.rf)
  }
  if(!(is.logical(holdout))){
    stop("Logical value required for 'holdout'.")
  }
  unbiased_importance <- if(holdout){
    if(importance != "permutation"){
      stop("Set importance to 'permutation' for holdout.")
    }
    ## train holdout RFs
    holdout.rf(x = x, y = y,
               ntree = ntree,
               mtry.prop = mtry.prop,
               nodesize.prop = nodesize.prop,
               no.threads = no.threads,
               type = type,
               importance = importance,
               replace = replace,
               sample.fraction = sample.fraction,
               ...)
  } else {
    if(importance != "impurity_corrected"){
      stop("Set importance to 'impurity_corrected' for corrected impurity.")
    }
    get_imp_ranger(x = x, y = y,
                   ntree = ntree,
                   mtry.prop = mtry.prop,
                   nodesize.prop = nodesize.prop,
                   no.threads = no.threads,
                   type = type,
                   importance = importance,
                   replace = replace,
                   sample.fraction = sample.fraction,
                   ...)
  }
  ## variable selection using importance_pvalues function
  res.janitza = ranger::importance_pvalues(x = unbiased_importance,
                                           method = "janitza",
                                           conf.level = 0.95)
  res.janitza = as.data.frame(res.janitza)
  colnames(res.janitza)[1] = "vim"
  ## Adjust p values if required
  res.janitza$pvalue <- if(fdr.adj){
    p.adj = p.adjust(p = res.janitza$pvalue, method = "BH")
  } else {
    res.janitza$pvalue
  }
  ## select variables
  ind.sel = as.numeric(res.janitza$pvalue == 0 | res.janitza$pvalue < p.t)

  ## info about variables
  info = data.frame(res.janitza, selected = ind.sel)
  return(list(info = info, var = sort(rownames(info)[info$selected == 1])))
}

#' Helper function for variable selection using Vita approach.
#'
#' This function calculates a modified version of the permutation importance using two cross-validation folds (holdout folds)
#' as described in Janitza et al. (2015). Note that this function is a reimplementation of the \code{holdoutRF} function in the
#' R package \code{\link[ranger]{ranger}}.
#'
#' @param x matrix or data.frame of predictor variables with variables in
#'   columns and samples in rows (Note: missing values are not allowed).
#' @param y vector with values of phenotype variable (Note: will be converted to factor if
#'   classification mode is used).
#' @param ntree number of trees.
#' @param mtry.prop proportion of variables that should be used at each split.
#' @param nodesize.prop proportion of minimal number of samples in terminal
#'   nodes.
#' @param no.threads number of threads used for parallel execution.
#' @param type mode of prediction ("regression", "classification" or "probability").
#' @param importance See \code{\link[ranger]{ranger}} for details.
#' @param replace See \code{\link[ranger]{ranger}} for details.
#' @param sample.fraction See \code{\link[ranger]{ranger}} for details.
#' @param case.weights See \code{\link[ranger]{ranger}} for details.
#' @param ... additional parameters passed to \code{ranger}.
#'
#' @return Hold-out random forests with variable importance
#'
#' @references
#' Janitza, S., Celik, E. & Boulesteix, A.-L., (2015). A computationally fast variable importance test for random forest for high dimensional data, Technical Report 185, University of Munich, https://epub.ub.uni-muenchen.de/25587.

holdout.rf <- function(x, y, ntree = 500,
                       mtry.prop = 0.2,
                       nodesize.prop = 0.1,
                       no.threads = 1,
                       type = "regression",
                       importance = importance,
                       replace = TRUE,
                       sample.fraction = ifelse(replace, 1, 0.632),
                       case.weights = NULL,
                       ...) {

  ## define two cross-validation folds
  n = nrow(x)
  weights = rbinom(n, 1, 0.5)

  ## train two RFs
  res = list(rf1 = wrapper.rf(x = x, y = y,
                              ntree = ntree, mtry.prop = mtry.prop,
                              nodesize.prop = nodesize.prop, no.threads = no.threads,
                              method = "ranger", type = type,
                              case.weights = weights, replace = replace,
                              sample.fraction = sample.fraction,
                              holdout = TRUE, importance = importance,
                              ...),
             rf2 = wrapper.rf(x = x, y = y,
                              ntree = ntree, mtry.prop = mtry.prop,
                              nodesize.prop = nodesize.prop, no.threads = no.threads,
                              method = "ranger", type = type,
                              case.weights = 1 - weights, replace = replace,
                              sample.fraction = sample.fraction,
                              holdout = TRUE,  importance = importance,
                              ...))

  ## calculate mean VIM
  res$variable.importance = (res$rf1$variable.importance +
                               res$rf2$variable.importance)/2
  res$treetype = res$rf1$treetype
  res$importance.mode = res$rf1$importance.mode
  class(res) = "holdoutRF"
  return(res)
}
