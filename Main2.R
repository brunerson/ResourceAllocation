
## Loading the data
data <- read.csv("LIDC dataset with full annotations.csv",header=TRUE)
img_fs <- data[,5:69]

## Multiple trials are run
t <- 20
sigma <- 0.8
lambda1 <- 1
lambda2 <- 0.2

## Output dataset
#just creates null vectors
train.output <- vector(mode="list",length=t)
test.output <- vector(mode="list",length=t)

## Information for label usage
label.nodule <- vector(mode="list",length=t)
label.output <- vector(mode="list",length=t)

## Progress bar for loop
pb <- txtProgressBar(min=1,max=t,style=3)

#t = number of trials
for(k in 1:t)
{  
  ## Loading the labels
  #makes sure each trail samples differently
  set.seed(k)
  labels <- data[,70:73]
  #shuffles labels
  labels <- t(apply(labels,1,sample))
  #labels becomes "num"? makes sets of labels per iteration
  labels <- cbind(labels[,1],apply(labels[,1:2],1,mode),
                  apply(labels[,1:3],1,mode),apply(labels,1,mode))
  labels <- apply(labels,c(1,2),rescale)
  
  ## Label tracker
  # 1 column, all values = 1
  #will be updated to keep track of new labels
  label.tracker <- rep(1,nrow(labels))
  
  ## Temporary output
  train.temp.output <- vector(mode="list",length=4)
  test.temp.output <- vector(mode="list",length=4)
  label.temp.output <- vector(mode="list",length=4)
  
  ## Reshuffle the training and testing datasets at the beginning of each trial
  for(r in 1:4)
  {
    set.seed(r)
    #selects new training set for each iteration
    index <- sample(810,540,replace=FALSE)
    train.img <- as.matrix(img_fs[index,])
    test.img <- as.matrix(img_fs[-index,])
    
    
    actual.label <- label.selector(labels,label.tracker)
    train.actual.label <- actual.label[index]
    test.actual.label <- actual.label[-index]
    
    ## Kernel Principal Component Analysis
    kpca.model <- kpca(train.img,kernel="rbfdot",kpar=list(sigma=sigma))
    train.rotated <- rotated(kpca.model)
    test.rotated <- predict(kpca.model,test.img)
    
    ## Regularized Canonical Correlation Analysis
    train.dummy <- t(sapply(train.actual.label,as.dummy))
    test.dummy <- t(sapply(test.actual.label,as.dummy))
    cca.model <- rcc(train.rotated,train.dummy,
                     lambda1=lambda1,lambda2=lambda2)
    train.score <- train.rotated %*% cca.model$xcoef 
    test.score <- test.rotated %*% cca.model$xcoef 
    
    ## Modified K-means Clustering
    #THIS IS WHERE CLASSIFICATION ACTUALLY HAPPENS
    train.cl.model <- kmeans(train.score,centers=3,iter.max=50,nstart=10)
    train.pred.label <- fitted(train.cl.model,method="class")
    centers <- train.cl.model$centers
    test.cl.model <- kmeans(test.score,centers=centers,iter.max=50)
    test.pred.label <- fitted(test.cl.model,method="class")
    
    ## Silhouette Coefficient
    train.sil <- mean(silhouette(train.pred.label,daisy(train.score))[,"sil_width"])
    test.sil <- mean(silhouette(test.pred.label,daisy(test.score))[,"sil_width"])
    
    ## Confusion Matrix
    p <- permutations(3)
    train.kappas <- vector(mode="list",length=nrow(p))
    test.kappas <- vector(mode="list",length=nrow(p))
    
    for(i in 1:nrow(p))
    {
      ## Function to map cluster numbers to group labels
      shuffle <- function(x)
      {
        ifelse(x==1,p[i,1],ifelse(x==2,p[i,2],p[i,3]))
      }
      
      train.kappas[i] <- kappa2(cbind(train.actual.label,sapply(train.pred.label,shuffle)),
                                weight="squared")$value
      test.kappas[i] <- kappa2(cbind(test.actual.label,sapply(test.pred.label,shuffle)),
                               weight="squared")$value  
    }
    
    good_shuffle <- function(x)
    {
      i <- which(train.kappas==max(unlist(train.kappas)))
      ifelse(x==1,p[i,1],ifelse(x==2,p[i,2],p[i,3]))
    }
    
    train.kappa <- max(unlist(train.kappas))
    test.kappa <- max(unlist(test.kappas))
    
    train.pred.label <- sapply(train.pred.label,good_shuffle)
    test.pred.label <- sapply(test.pred.label,good_shuffle)
    pred.label <- vector(mode="list",length(actual.label))
    pred.label[index] <- train.pred.label
    pred.label[-index] <- test.pred.label
    pred.label <- unlist(pred.label)
    
    ## Rand Index
    train.rand <- RRand(train.actual.label,train.pred.label)$Rand
    test.rand <- RRand(test.actual.label,test.pred.label)$Rand
    
    ## Update the label tracker
    if(r!=4)
    {
      miss.index <- which(pred.label!=actual.label)
      label.tracker[miss.index] <- label.tracker[miss.index]+1
    }
    
    ## Save the output for the current iteration
    #results for training and testing for this iteration
    train.temp.output[[r]] <- c(r,train.sil,train.rand,train.kappa)
    test.temp.output[[r]] <- c(r,test.sil,test.rand,test.kappa)
    #total misclassified
    label.temp.output[[r]] <- sum(pred.label!=actual.label)
  }
  
  ## Save the output for the current trial
  train.output[[k]] <- train.temp.output
  test.output[[k]] <- test.temp.output
  label.output[[k]] <- label.temp.output
  label.nodule[[k]] <- label.tracker
  
  ## Refresh progress bar
  setTxtProgressBar(pb,k)
}

train.output <- matrix(unlist(train.output),ncol=4,byrow=TRUE)
test.output <- matrix(unlist(test.output),ncol=4,byrow=TRUE)

train.mean.output <- rbind(iter.mean.calculator(train.output,1),
                           iter.mean.calculator(train.output,2),
                           iter.mean.calculator(train.output,3),
                           iter.mean.calculator(train.output,4))
test.mean.output <- rbind(iter.mean.calculator(test.output,1),
                          iter.mean.calculator(test.output,2),
                          iter.mean.calculator(test.output,3),
                          iter.mean.calculator(test.output,4))

## Confidence Interval for Rand index
train.rand.ci.output <- rbind(iter.rand.ci.calculator(train.output,1),
                              iter.rand.ci.calculator(train.output,2),
                              iter.rand.ci.calculator(train.output,3),
                              iter.rand.ci.calculator(train.output,4))
test.rand.ci.output <- rbind(iter.rand.ci.calculator(test.output,1),
                             iter.rand.ci.calculator(test.output,2),
                             iter.rand.ci.calculator(test.output,3),
                             iter.rand.ci.calculator(test.output,4))

## Confidence Interval for Cohen's Kappa
train.kappa.ci.output <- rbind(iter.kappa.ci.calculator(train.output,1),
                               iter.kappa.ci.calculator(train.output,2),
                               iter.kappa.ci.calculator(train.output,3),
                               iter.kappa.ci.calculator(train.output,4))
test.kappa.ci.output <- rbind(iter.kappa.ci.calculator(test.output,1),
                              iter.kappa.ci.calculator(test.output,2),
                              iter.kappa.ci.calculator(test.output,3),
                              iter.kappa.ci.calculator(test.output,4))

## Trend plot for Rand index
matplot(1:4,cbind(train.mean.output[,3],test.mean.output[,3]),type="l",col="black",
        lty=2,las=1,ylim=c(0.4,0.9),xlab="Number of Iterations",
        ylab="Average Rand Index",main="Performance Chart in Rand Index",
        xaxp=c(1,4,3))
matpoints(1:4,cbind(train.mean.output[,3],test.mean.output[,3]),col="gray",
          bg=c("red","blue"),pch=21)
legend("bottomright",legend=c("training","testing"),pch=21,col="gray",
       pt.bg=c("red","blue"),bty="n")
arrows(1:4,train.rand.ci.output[,1],1:4,train.rand.ci.output[,2],angle=90,code=3,
       length=0.05)
arrows(1:4,test.rand.ci.output[,1],1:4,test.rand.ci.output[,2],angle=90,code=3,
       length=0.05)

## Trend plot for Cohen's Kappa
matplot(1:4,cbind(train.mean.output[,4],test.mean.output[,4]),type="l",col="black",
        lty=2,las=1,ylim=c(0.4,0.9),xlab="Number of Iterations",
        ylab="Average Cohen's Kappa",main="Performance Chart in Cohen's Kappa",
        xaxp=c(1,4,3))
matpoints(1:4,cbind(train.mean.output[,4],test.mean.output[,4]),col="gray",
          bg=c("red","blue"),pch=21)
arrows(1:4,train.kappa.ci.output[,1],1:4,train.kappa.ci.output[,2],angle=90,code=3,
       length=0.05)
arrows(1:4,test.kappa.ci.output[,1],1:4,test.kappa.ci.output[,2],angle=90,code=3,
       length=0.05)

## Single trial that is most representative
deviance <- abs(test.output[seq(4,4*t,4),3]-mean(test.output[seq(4,4*t,4),3]))
best.trial <- which(deviance==min(deviance))

## Histogram: average number of labels 
label.total <- t(matrix(unlist(label.output),ncol=20))
label.invd <- matrix(unlist(label.nodule),ncol=20)
mean.label.invd <- apply(label.invd,1,mean)
h1 <- hist(mean.label.invd,col="skyblue",plot=FALSE,warn.unused=FALSE)
cols <- c(rep("skyblue",sum(h1$breaks<2)),rep("lightpink",sum(h1$breaks>=2)))
h2 <- hist(mean.label.invd,col=cols,las=1,border="brown",xlab="",
           ylab="Frequency",main="Histogram of Average Number of Labels Used",
           ylim=c(0,140))
legend(3.5,130,c("easy","hard"),fill=c("skyblue","lightpink"),
       border="brown",box.lty=3,adj=c(0,0.35))

## Bar chart: additional labels
mean.label.total <- apply(label.total,2,mean)
confint.label.total <- apply(label.total,2,function(x) t.test(x)$conf.int)
bp <- barplot(mean.label.total,col=alpha("red",0.5),las=1,ylim=c(0,400),
              names.arg=c("1 ==> 2","2 ==> 3","3 ==> 4","4 ==> 5 if any"),
              xlab="Stream of Iterations",y="Number of Additional Labels")
arrows(bp,confint.label.total[1,],bp,confint.label.total[2,],angle=90,code=3,length=0.5)
text(bp,50,labels=round(mean.label.total),col="blue",font=2)
text(bp,confint.label.total[1,],labels=round(confint.label.total[1,]),
     pos=1,col="red",font=2,cex=0.8)
text(bp,confint.label.total[2,],labels=round(confint.label.total[2,]),
     pos=3,col="red",font=2,cex=0.8)

## Relationship between Rating Variability Index and average number of label
h.index <- ifelse(mean.label.invd<=2,0,1)
orig.label <- data[,70:73]
label.rvi <- apply(orig.label,1,rvi)

bp <- barplot(prop.table(table(label.rvi,h.index),2),beside=TRUE,
              names.arg=c("Easy \n (mean=0.817)","Hard \n (mean=0.919)"),
              col=heat.colors(length(unique(label.rvi))),
              ylim=c(-0.05,0.4),las=1,xlab="Rating Variability Index",
              ylab="Counts in Frequency",cex.names=0.8)
text(bp,prop.table(table(label.rvi,h.index),2),
     labels=table(label.rvi,h.index),pos=3,cex=0.6,col="blue",font=2)
text(bp,0,labels=sort(unique(label.rvi)),pos=1,cex=0.5,font=2)

rvi.hard <- label.rvi[which(h.index==1)]
rvi.easy <- label.rvi[which(h.index==0)]
t.test(rvi.hard,rvi.easy,alternative="greater")







