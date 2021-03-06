wtd.mean <- function(x, weights=NULL, normwt='ignored', na.rm=TRUE)
{
  if(!length(weights)) return(mean(x, na.rm=na.rm))
  if(na.rm) {
    s <- !is.na(x + weights)
    x <- x[s]
    weights <- weights[s]
  }

  sum(weights*x)/sum(weights)
}


wtd.var <- function(x, weights=NULL, normwt=FALSE, na.rm=TRUE)
{
  if(!length(weights)) {
    if(na.rm) x <- x[!is.na(x)]
    return(var(x))
  }

  if(na.rm) {
    s <- !is.na(x + weights)
    x <- x[s]
    weights <- weights[s]
  }

  if(normwt)
    weights <- weights * length(x) / sum(weights)

  sw <- sum(weights)
  xbar <- sum(weights * x) / sw
  sum(weights*((x - xbar)^2)) / (sw - sum(weights ^ 2) / sw)
}


wtd.quantile <- function(x, weights=NULL, probs=c(0, .25, .5, .75, 1), 
                         type=c('quantile','(i-1)/(n-1)','i/(n+1)','i/n'), 
                         normwt=FALSE, na.rm=TRUE)
{
  if(!length(weights))
    return(quantile(x, probs=probs, na.rm=na.rm))

  type <- match.arg(type)
  if(any(probs < 0 | probs > 1))
    stop("Probabilities must be between 0 and 1 inclusive")

  nams <- paste(format(round(probs * 100, if(length(probs) > 1) 
                             2 - log10(diff(range(probs))) else 2)), 
                "%", sep = "")

  if(type=='quantile') {
    w <- wtd.table(x, weights, na.rm=na.rm, normwt=normwt, type='list')
    x     <- w$x
    wts   <- w$sum.of.weights
    n     <- sum(wts)
    order <- 1 + (n - 1) * probs
    low   <- pmax(floor(order), 1)
    high  <- pmin(low + 1, n)
    order <- order %% 1
    ## Find low and high order statistics
    ## These are minimum values of x such that the cum. freqs >= c(low,high)
    allq <- approx(cumsum(wts), x, xout=c(low,high), 
                   method='constant', f=1, rule=2)$y
    k <- length(probs)
    quantiles <- (1 - order)*allq[1:k] + order*allq[-(1:k)]
    names(quantiles) <- nams
    return(quantiles)
  } 
  w <- wtd.Ecdf(x, weights, na.rm=na.rm, type=type, normwt=normwt)
  structure(approx(w$ecdf, w$x, xout=probs, rule=2)$y, 
            names=nams)
}


wtd.Ecdf <- function(x, weights=NULL, 
                     type=c('i/n','(i-1)/(n-1)','i/(n+1)'), 
                     normwt=FALSE, na.rm=TRUE)
{
  type <- match.arg(type)
  switch(type,
         '(i-1)/(n-1)'={a <- b <- -1},
         'i/(n+1)'    ={a <- 0; b <- 1},
         'i/n'        ={a <- b <- 0})

  if(!length(weights)) {
    ##.Options$digits <- 7  ## to get good resolution for names(table(x))6Aug00
    oldopt <- options(digits=7)
    on.exit(options(oldopt))
    cumu <- table(x)    ## R does not give names for cumsum
    isdate <- testDateTime(x)  ## 31aug02
    ax <- attributes(x)
    ax$names <- NULL
    x <- as.numeric(names(cumu))
    if(isdate) attributes(x) <- c(attributes(x),ax)
    cumu <- cumsum(cumu)
    cdf <- (cumu + a)/(cumu[length(cumu)] + b)
    if(cdf[1]>0) {
      x <- c(x[1], x);
      cdf <- c(0,cdf)
    }

    return(list(x = x, ecdf=cdf))
  }

  w <- wtd.table(x, weights, normwt=normwt, na.rm=na.rm)
  cumu <- cumsum(w$sum.of.weights)
  cdf <- (cumu + a)/(cumu[length(cumu)] + b)
  list(x = c(if(cdf[1]>0) w$x[1], w$x), ecdf=c(if(cdf[1]>0)0, cdf))
}


wtd.table <- function(x, weights=NULL, type=c('list','table'), 
                      normwt=FALSE, na.rm=TRUE)
{
  type <- match.arg(type)
  if(!length(weights))
    weights <- rep(1, length(x))

  isdate <- testDateTime(x)  ## 31aug02 + next 2
  ax <- attributes(x)
  ax$names <- NULL
  
  if(is.character(x)) x <- as.factor(x)
  lev <- levels(x)
  x <- unclass(x)
  
  if(na.rm) {
    s <- !is.na(x + weights)
    x <- x[s, drop=FALSE]    ## drop is for factor class
    weights <- weights[s]
  }

  n <- length(x)
  if(normwt)
    weights <- weights * length(x) / sum(weights)

  i <- order(x)  # R does not preserve levels here
  x <- x[i]; weights <- weights[i]

  if(any(duplicated(x))) {  ## diff(x) == 0 faster but doesn't handle Inf
    weights <- tapply(weights, x, sum)
    if(length(lev)) {
      levused <- lev[sort(unique(x))]
      if((length(weights) > length(levused)) &&
         any(is.na(weights)))
        weights <- weights[!is.na(weights)]

      if(length(weights) != length(levused))
        stop('program logic error')

      names(weights) <- levused
    }

    if(!length(names(weights)))
      stop('program logic error')

    if(type=='table')
      return(weights)

    x <- all.is.numeric(names(weights), 'vector')
    if(isdate)
      attributes(x) <- c(attributes(x),ax)

    names(weights) <- NULL
    return(list(x=x, sum.of.weights=weights))
  }

  xx <- x
  if(isdate)
    attributes(xx) <- c(attributes(xx),ax)

  if(type=='list')
    list(x=if(length(lev))lev[x]
           else xx, 
         sum.of.weights=weights)
  else {
    names(weights) <- if(length(lev)) lev[x]
                      else xx
    weights
  }
}


wtd.rank <- function(x, weights=NULL, normwt=FALSE, na.rm=TRUE)
{
  if(!length(weights))
    return(rank(x, na.last=if(na.rm) NA else TRUE))

  tab <- wtd.table(x, weights, normwt=normwt, na.rm=na.rm)
  
  freqs <- tab$sum.of.weights
  ## rank of x = # <= x - .5 (# = x, minus 1)
  r <- cumsum(freqs) - .5*(freqs-1)
  ## Now r gives ranks for all unique x values.  Do table look-up
  ## to spread these ranks around for all x values.  r is in order of x
  approx(tab$x, r, xout=x)$y
}


wtd.loess.noiter <- function(x, y, weights=rep(1,n),
                             span=2/3, degree=1, cell=.13333, 
                             type=c('all','ordered all','evaluate'), 
                             evaluation=100, na.rm=TRUE) {
  type <- match.arg(type)
  n <- length(y)
  if(na.rm) {
    s <- !is.na(x+y+weights)
    x <- x[s]; y <- y[s]; weights <- weights[s]; n <- length(y)
  }
  
  max.kd <- max(200, n)
  # y <- stats:::simpleLoess(y, x, weights=weights, span=span,
  #                          degree=degree, cell=cell)$fitted
  y <- fitted(loess(y ~ x, weights=weights, span=span, degree=degree,
		control=loess.control(cell=cell, iterations=1)))

  switch(type,
         all=list(x=x, y=y),
         'ordered all'={
           i <- order(x);
           list(x=x[i],y=y[i])
         },
         evaluate={
           r <- range(x, na.rm=na.rm)
           approx(x, y, xout=seq(r[1], r[2], length=evaluation))
         })
}

num.denom.setup <- function(num, denom)
{
  n <- length(num)
  if(length(denom) != n)
    stop('lengths of num and denom must match')
  
  s <- (1:n)[!is.na(num + denom) & denom != 0]
  num <- num[s];
  denom <- denom[s]
  
  subs <- s[num > 0]
  y <- rep(1, length(subs))
  wt <- num[num > 0]
  other <- denom - num
  subs <- c(subs, s[other > 0])
  wt <- c(wt, other[other > 0])
  y <- c(y, rep(0, sum(other>0)))
  list(subs=subs, weights=wt, y=y)
}
