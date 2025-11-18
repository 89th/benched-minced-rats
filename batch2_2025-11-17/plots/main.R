library(dplyr)
library(stringr)
library(ggplot2)
# Time conversions
{
  convert_epoch_to_RFC3339 <- function (epoch){
    dt_utc <- as.POSIXct(epoch, origin = "1970-01-01", tz = "America/Chicago")
    rfc_utc <- format(dt_utc, "%Y-%m-%d %H:%M:%S%z")
    rfc_utc_colon <- sub("(\\+|\\-)(\\d{2})(\\d{2})$", "\\1\\2:\\3", rfc_utc)
    return (rfc_utc_colon)
  }
  convert_RFC3339_to_epoch <- function (datetime){
    return (as.numeric(as.POSIXct(datetime %>% str_replace(":(\\d{2})$","\\1"), format = "%Y-%m-%d %H:%M:%S%z", tz = "UTC")))
  }
  
  convert_RFC3339_truncated_to_epoch <- function (datetime){
    return (as.numeric(as.POSIXct(datetime %>% str_replace("$","-0600"), format = "%Y-%m-%d %H:%M:%S%z", tz = "UTC")))
  }
  
  convert_humantime_to_epoch <- function (time){
    return (as.numeric(as.POSIXct(time %>% str_replace("$","-0600"), format = "%Y-%m-%d %H:%M:%S%z", tz = "UTC")))
  }
  
  convert_plainhumantime_to_epoch <- function (time){
    return (as.numeric(as.POSIXct(time %>% str_replace("$","-0600"), format = "%Y%m%d %H%M%S%z", tz = "UTC")))
  }
}

# # GPU logs
# {
#   logs_gpu <- read.csv("../system_logs/vmstat_gpu_consolidated.log")
#   
#   logs_gpu <- mutate(logs_gpu, timerfc = if_else(timerfc=="", convert_epoch_to_RFC3339(timestamp), timerfc))
#   logs_gpu <- mutate(logs_gpu, timestamp = if_else(timestamp=="" | is.na(timestamp), convert_RFC3339_to_epoch(timerfc), timestamp))
#   
#   ggplot()+
#     geom_point(data = logs_gpu, aes(x=timestamp,y=GPU.use...),color="purple",size=0.5)
#   ggplot()+
#     geom_point(data = logs_gpu, aes(x=timestamp,y=GPU.Memory.Allocated..VRAM.),color="green",size=0.5)
#   ggplot()+
#     geom_point(data = logs_gpu, aes(x=timestamp,y=GPU.Memory.Read.Write.Activity...),color="blue",size=0.5)
# }
# 
# 
# # CPU + Memory logs
# {
#   logs_cpumem <- read.csv("../system_logs/vmstat_cpumem_1763070507.tsv", sep = "\t")
# 
#   logs_cpumem$timerfc <- logs_cpumem$CST
#   logs_cpumem <- mutate(logs_cpumem, timestamp = convert_RFC3339_truncated_to_epoch(timerfc))
# 
#   ggplot()+
#     geom_point(data=logs_cpumem, aes(x=timestamp,y=us))+
#     geom_point(data = logs_gpu, aes(x=timestamp,y=GPU.use...),color="purple",size=0.5)
# }
# 
# 
# # Disk IO logs
# {
#   logs_disk <- read.csv("../system_logs/vmstat_disk_1763070511.tsv", sep = "\t")
#   
#   usual_suspects = c("nvme0n1", "nvme1n1", "nvme2n1", "nvme3n1")
#   logs_disk$timerfc <- logs_disk$CST
#   logs_disk <- mutate(logs_disk, timestamp = convert_RFC3339_truncated_to_epoch(timerfc))
#   
#   ggplot()+
#     geom_point(data=logs_disk[logs_disk$disk %in% usual_suspects,], aes(x=timestamp,y=total.1/(100000),color=disk),size=0.1)+
#     geom_point(data = logs_gpu, aes(x=timestamp,y=GPU.Memory.Read.Write.Activity...),color="blue",size=0.5)
# }

# Ingesting the chunky dataset
{
  samples_meta = read.csv("meta.tsv", sep = "\t", header = T)
  
  logs_chunky <- data.frame()
  logs_spark <- data.frame()
  for (sample_filename in levels(factor(samples_meta$filename))){
    sample_stats <- read.csv(paste0("../chunky_tsvs/", sample_filename, ".tsv"), header = F, sep = "\t")
    colnames(sample_stats) <- c("human_time","chunks","eta","cps")
    
    metadata = samples_meta[samples_meta$filename %in% sample_filename,]
    sample_stats <- mutate(sample_stats, timestamp = convert_humantime_to_epoch(human_time))
    sample_stats$filename <- metadata$filename
    sample_stats$java <- metadata$java
    sample_stats$args <- metadata$args
    sample_stats$replicate <- metadata$replicate
    sample_stats$timestamp_tared <- sample_stats$timestamp - min(sample_stats$timestamp)
    logs_chunky <- rbind(logs_chunky, sample_stats)
    
    
    sample_spark <- read.csv(paste0("../spark_tsvs/", sample_filename, ".tsv"), header = F, sep = "\t")
    colnames(sample_spark) <- c("human_time","heap","max_heap")
    
    sample_spark <- mutate(sample_spark, timestamp = convert_humantime_to_epoch(human_time))
    sample_spark$filename <- metadata$filename
    sample_spark$java <- metadata$java
    sample_spark$args <- metadata$args
    sample_spark$replicate <- metadata$replicate
    sample_spark$timestamp_tared <- sample_spark$timestamp - min(sample_spark$timestamp)
    logs_spark <- rbind(logs_spark, sample_spark)
  }
  
  {
    minmin <- min(logs_chunky$timestamp,logs_spark$timestamp)
    
    logs_chunky$timestamp_elapsed_overall <- (logs_chunky$timestamp - minmin)/3600
    logs_spark$timestamp_elapsed_overall <- (logs_spark$timestamp - minmin)/3600
    
    p <- ggplot(data=logs_chunky,mapping = aes(x=timestamp_elapsed_overall))+
      geom_point(data=logs_chunky,aes(x=timestamp_elapsed_overall, y=cps/25,color=paste0(java,args,replicate)), size=0.5, alpha=0.05, shape = 5)+
      geom_point(data=logs_spark, aes(x=timestamp_elapsed_overall, y=heap),color="#27CFF5", size=0.5, alpha=0.05, shape = 1)+
      geom_point(data=logs_spark, aes(x=timestamp_elapsed_overall, y=max_heap),color="#DE2100", size=0.5, alpha=0.05, shape = 3)+
      scale_y_continuous( name = 'Heap (GB)', sec.axis = sec_axis(~. * 25,name = "Chunks per second"), limits = c(0,89))+
      labs(x = "Elapsed time (hours)",
           title = paste0("CPS over whole of batch 2"),
           subtitle = paste0("red line is max heap, blue is current heap"))+
      theme(legend.position = "none")
    ggsave(filename = paste0("results/chunks_rates.pdf"),plot = p, width = 20, height = 9)
  }
  
  # Removing poorly-threaded JVM args test
  logs_chunky <- logs_chunky[!logs_chunky$args %in% c("none_user_jvm_args"),]
  
  
  for (javatype in levels(factor(samples_meta$java))){
    p <- ggplot(data=logs_chunky[logs_chunky$java %in% c(javatype),],mapping = aes(x=timestamp_tared))+
      geom_point(aes(x=timestamp_tared, y=cps*750,color=args), size=0.5, alpha=0.05, shape = 4)+
      geom_point(mapping = aes(y=chunks,color=args), size=0.5, alpha=0.01)+theme_bw()+
      geom_smooth(aes(y=chunks,color=args),method = "lm", linewidth = 0.3,formula=y~x+0,linetype = 5)+
      scale_y_continuous( name = 'Chunks generated', sec.axis = sec_axis(~. / 750,name = "Chunks per second"))+
      labs(x = "Time elapsed (seconds)",
           title = paste0("Chunks generated over time - ",javatype),
           subtitle = paste0("Same seed. Different JVM args. 4 replicates each."))
    ggsave(filename = paste0("results/chunks_over_time_",javatype,".pdf"),plot = p, width = 9, height = 6)
  }
}