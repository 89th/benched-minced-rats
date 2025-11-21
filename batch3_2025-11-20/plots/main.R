library(dplyr)
library(stringr)
library(ggplot2)
library(data.table)

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
  
  convert_plainhumantime_to_epoch <- function (time){
    return (as.numeric(as.POSIXct(time %>% str_replace("$","-0600"), format = "%Y%m%d %H%M%S%z", tz = "UTC")))
  }
  
  convert_humanelapsedtime_to_seconds <- function (humanelapsedtime){
    convert_one_humanelapsedtime <- function (onetime){
      onetimesplit = as.numeric(str_split_1(onetime,":"))
      return (onetimesplit[1]*3600 + onetimesplit[2]*60 + onetimesplit[3]*1)
    }
    return (sapply(humanelapsedtime,convert_one_humanelapsedtime))
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
  
  samples_checkpoints = read.csv("../checkpoints_tsvs/benchmarks_checkpoints.tsv", sep = "\t", header = T)
  for (human_time_entry in colnames(samples_checkpoints)[colnames(samples_checkpoints) %like% "human_time$"]){
    samples_checkpoints[[human_time_entry %>% str_replace("human_time$","timestamp")]] <- convert_RFC3339_truncated_to_epoch(samples_checkpoints[[human_time_entry]])
  }
  samples_checkpoints$chunky_elapsed_time_seconds <- convert_humanelapsedtime_to_seconds(samples_checkpoints$chunky_elapsed_time)
  samples_checkpoints$java <- ""
  samples_checkpoints$args <- ""
  samples_checkpoints$replicate <- ""
  samples_checkpoints$avg_heap <- 0
  
  logs_chunky <- data.frame()
  logs_spark <- data.frame()
  for (sample_filename in levels(factor(samples_meta$filename))){
    sample_stats <- read.csv(paste0("../chunky_tsvs/", sample_filename, ".tsv"), header = F, sep = "\t")
    colnames(sample_stats) <- c("human_time","chunks","eta","cps")
    
    metadata = samples_meta[samples_meta$filename %in% sample_filename,]
    sample_stats <- mutate(sample_stats, timestamp = convert_RFC3339_truncated_to_epoch(human_time))
    sample_stats$filename <- metadata$filename
    sample_stats$java <- metadata$java
    sample_stats$args <- metadata$args
    sample_stats$replicate <- metadata$replicate
    sample_stats$timestamp_tared <- sample_stats$timestamp - min(sample_stats$timestamp)
    logs_chunky <- rbind(logs_chunky, sample_stats)
    
    
    sample_spark <- read.csv(paste0("../spark_tsvs/", sample_filename, ".tsv"), header = F, sep = "\t")
    colnames(sample_spark) <- c("human_time","heap","max_heap")
    
    sample_spark <- mutate(sample_spark, timestamp = convert_RFC3339_truncated_to_epoch(human_time))
    sample_spark$filename <- metadata$filename
    sample_spark$java <- metadata$java
    sample_spark$args <- metadata$args
    sample_spark$replicate <- metadata$replicate
    sample_spark$timestamp_tared <- sample_spark$timestamp - min(sample_spark$timestamp)
    logs_spark <- rbind(logs_spark, sample_spark)
    
    samples_checkpoints[samples_checkpoints$filename %in% sample_filename,]$java <- metadata$java
    samples_checkpoints[samples_checkpoints$filename %in% sample_filename,]$args <- metadata$args
    samples_checkpoints[samples_checkpoints$filename %in% sample_filename,]$replicate <- metadata$replicate
    samples_checkpoints[samples_checkpoints$filename %in% sample_filename,]$avg_heap <- mean(sample_spark$heap)
  }
  
  {
    minmin <- min(logs_chunky$timestamp,logs_spark$timestamp)
    
    logs_chunky$timestamp_elapsed_overall <- (logs_chunky$timestamp - minmin)/3600
    logs_spark$timestamp_elapsed_overall <- (logs_spark$timestamp - minmin)/3600
    
    p <- ggplot(data=logs_chunky,mapping = aes(x=timestamp_elapsed_overall))+
      geom_point(data=logs_chunky,aes(x=timestamp_elapsed_overall, y=cps/25,color=paste0(java,args,replicate)), size=0.5, alpha=0.3, shape = 5)+
      geom_point(data=logs_spark, aes(x=timestamp_elapsed_overall, y=heap),color="#27CFF5", size=0.5, alpha=0.5, shape = 1)+
      geom_point(data=logs_spark, aes(x=timestamp_elapsed_overall, y=max_heap),color="#DE2100", size=0.5, alpha=0.05, shape = 3)+
      scale_y_continuous( name = 'Heap (GB)', sec.axis = sec_axis(~. * 25,name = "Chunks per second"), limits = c(0,89))+
      labs(x = "Elapsed time (hours)",
           title = paste0("CPS over whole of batch 2"),
           subtitle = paste0("red line is max heap, blue is current heap"))+
      theme(legend.position = "none")
    
    for (args_name in levels(factor(logs_chunky$args))){
      for (java_name in levels(factor(logs_chunky$java))){
        print(paste0(args_name," (",java_name,")"))
        p <- p+
          annotate(geom = "text",
                   x=mean(logs_chunky[logs_chunky$args %in% args_name & logs_chunky$java %in% java_name,]$timestamp_elapsed_overall),
                   y=25,
                   angle=90,
                   hjust=0,
                   label=paste0(java_name," (",args_name,")"))
      }
    }
    ggsave(filename = paste0("results/chunks_rates.pdf"),plot = p, width = 20, height = 9)
  }
  
  # Plotting time series data for each java
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
  
  # Plotting bar charts to compare single-number results from each run
  {
    # Chunky elapsed time
    {
      p <- ggplot(samples_checkpoints) +
        geom_boxplot(data = samples_checkpoints,aes(x = factor(paste0(java," (",args,")")), y = chunky_elapsed_time_seconds, color = args, group = paste0(java,"_",args)),position = position_dodge(width = 4), fill = "black", outlier.size = 0.5, outlier.shape = 4, alpha=1) +
        geom_pointrange(data = samples_checkpoints,
                        aes(x = factor(paste0(java," (",args,")")),
                            y = chunky_elapsed_time_seconds,
                            color = args,
                            ymin=chunky_elapsed_time_seconds,
                            ymax=chunky_elapsed_time_seconds,
                            size = avg_heap,
                            shape = java),
                        linewidth = 0.5,
                        position=position_jitterdodge(dodge.width=4, jitter.width = 0.5)) +
        scale_size_continuous(limits = c(min(samples_checkpoints$avg_heap, na.rm = TRUE), max(samples_checkpoints$avg_heap, na.rm = TRUE)),range   = c(0.2, 1))+
        labs(x = "Test group",
             y = paste0("Chunky elapsed time (seconds)"),
             title = paste0("Chunky timings (lower is better)"),
             subtitle = paste0("Same seed. Different JVM and args. 4 replicates each.")) +
        theme_minimal()+
        theme(axis.text.x = element_text(angle = 45, vjust = 1, hjust=1))
      ggsave(filename = paste0("results/chunky_elapsed_time_all.pdf"), plot = p, width = 15, height = 5, scale = 1.5)
    }
    
    # Server startup time
    {
      p <- ggplot(samples_checkpoints) +
        geom_boxplot(data = samples_checkpoints,aes(x = factor(paste0(java," (",args,")")), y = elapsed_time_ms/1000, color = args, group = paste0(java,"_",args)),position = position_dodge(width = 4), fill = "black", outlier.size = 0.5, outlier.shape = 4, alpha=1) +
        geom_pointrange(data = samples_checkpoints,
                        aes(x = factor(paste0(java," (",args,")")),
                            y = elapsed_time_ms/1000,
                            color = args,
                            ymin=elapsed_time_ms/1000,
                            ymax=elapsed_time_ms/1000,
                            size = avg_heap,
                            shape = java),
                        linewidth = 0.5,
                        position=position_jitterdodge(dodge.width=4, jitter.width = 0.5)) +
        scale_size_continuous(limits = c(min(samples_checkpoints$avg_heap, na.rm = TRUE), max(samples_checkpoints$avg_heap, na.rm = TRUE)),range   = c(0.2, 1))+
        labs(x = "Test group",
             y = paste0("Server startup elapsed time (seconds)"),
             title = paste0("Startup timings (lower is better)"),
             subtitle = paste0("Same seed. Different JVM and args. 4 replicates each.")) +
        theme_minimal()+
        theme(axis.text.x = element_text(angle = 45, vjust = 1, hjust=1))
      ggsave(filename = paste0("results/startup_elapsed_time_all.pdf"), plot = p, width = 15, height = 5, scale = 1.5)
    }
    
    # Overall run elapsed time
    {
      p <- ggplot(samples_checkpoints) +
        geom_boxplot(data = samples_checkpoints,aes(x = factor(paste0(java," (",args,")")), y = chunky_end_timestamp - script_start_timestamp, color = args, group = paste0(java,"_",args)),position = position_dodge(width = 4), fill = "black", outlier.size = 0.5, outlier.shape = 4, alpha=1) +
        geom_pointrange(data = samples_checkpoints,
                        aes(x = factor(paste0(java," (",args,")")),
                            y = chunky_end_timestamp - script_start_timestamp,
                            color = args,
                            ymin=chunky_end_timestamp - script_start_timestamp,
                            ymax=chunky_end_timestamp - script_start_timestamp,
                            size = avg_heap,
                            shape = java),
                        linewidth = 0.5,
                        position=position_jitterdodge(dodge.width=4, jitter.width = 0.5)) +
        scale_size_continuous(limits = c(min(samples_checkpoints$avg_heap, na.rm = TRUE), max(samples_checkpoints$avg_heap, na.rm = TRUE)),range   = c(0.2, 1))+
        labs(x = "Test group",
             y = paste0("Overall run elapsed time (seconds)"),
             title = paste0("Overall run time (lower is better)"),
             subtitle = paste0("Same seed. Different JVM and args. 4 replicates each.")) +
        theme_minimal()+
        theme(axis.text.x = element_text(angle = 45, vjust = 1, hjust=1))
      ggsave(filename = paste0("results/overall_run_elapsed_time_all.pdf"), plot = p, width = 15, height = 5, scale = 1.5)
    }
    
    # Calculated chunks per second
    {
      p <- ggplot(samples_checkpoints) +
        geom_boxplot(data = samples_checkpoints,aes(x = factor(paste0(java," (",args,")")), y = chunky_chunks/(chunky_elapsed_time_seconds), color = args, group = paste0(java,"_",args)),position = position_dodge(width = 4), fill = "black", outlier.size = 0.5, outlier.shape = 4, alpha=1) +
        geom_pointrange(data = samples_checkpoints,
                        aes(x = factor(paste0(java," (",args,")")),
                            y = chunky_chunks/(chunky_elapsed_time_seconds),
                            color = args,
                            ymin=chunky_chunks/(chunky_elapsed_time_seconds), #I'll bother with this eventually
                            ymax=chunky_chunks/(chunky_elapsed_time_seconds),
                            size = avg_heap,
                            shape = java),
                        linewidth = 0.5,
                        position=position_jitterdodge(dodge.width=4, jitter.width = 0.5)) +
        scale_size_continuous(limits = c(min(samples_checkpoints$avg_heap, na.rm = TRUE), max(samples_checkpoints$avg_heap, na.rm = TRUE)),range   = c(0.2, 1))+
        labs(x = "Test group",
             y = paste0("Calculated chunks per second (total chunks / elapsed seconds)"),
             title = paste0("Calculated chunks per second (higher is better)"),
             subtitle = paste0("Same seed. Different JVM and args. 4 replicates each.")) +
        theme_minimal()+
        theme(axis.text.x = element_text(angle = 45, vjust = 1, hjust=1))
      ggsave(filename = paste0("results/calculated_chunks-per-second_all.pdf"), plot = p, width = 15, height = 5, scale = 1.5)
    }
  }
}