#' Launch ICE Train Status Dashboard
#'
#' Starts a Shiny app that periodically queries the Deutsche Bahn ICE Portal
#' API and displays real-time time series plots of train status data.
#'
#' @param poll_interval_sec Polling interval in seconds (default: 10).
#' @param ... Additional arguments passed to \code{\link[shiny]{shinyApp}}.
#'
#' @return A Shiny app object (launched in the browser).
#' @export
#'
#' @examples
#' \dontrun{
#' launch_dashboard()
#' launch_dashboard(poll_interval_sec = 5)
#' }
launch_dashboard <- function(poll_interval_sec = 10, ...) {
  app <- build_app(poll_interval_sec)
  shiny::runApp(app, ...)
}

# Helper: color for internet quality
internet_color <- function(val) {
  switch(as.character(val),
    "HIGH"     = "#309700",
    "MIDDLE"   = "#d4a017",
    "WEAK"     = "#e87000",
    "UNSTABLE" = "#ec0016",
    "NO_INFO"  = "#999999",
    "#999999"
  )
}

# Helper: color for GPS status
gps_color <- function(val) {
  switch(as.character(val),
    "VALID"   = "#309700",
    "INVALID" = "#ec0016",
    "#999999"
  )
}

# Try to load Germany sf geometry for route background
germany_sf <- function() {
  tryCatch({
    if (requireNamespace("rnaturalearth", quietly = TRUE) &&
        requireNamespace("sf", quietly = TRUE)) {
      rnaturalearth::ne_countries(
        country = "germany", scale = "medium", returnclass = "sf"
      )
    }
  }, error = function(e) NULL)
}

#' Build the Shiny app object (without launching)
#'
#' @param poll_interval_sec Polling interval in seconds.
#' @return A Shiny app object.
#' @keywords internal
build_app <- function(poll_interval_sec = 10) {

  # Pre-load Germany geometry once at app build time
  de_geom <- germany_sf()

  ui <- shiny::fluidPage(
    shiny::tags$head(
      shiny::tags$style(shiny::HTML("
        body { background-color: #f5f5f5; }
        .header { background-color: #ec0016; color: white; padding: 15px 20px;
                   margin: -15px -15px 20px -15px; }
        .header h2 { margin: 0; }
        .metric-box { background: white; border-radius: 8px; padding: 15px;
                       text-align: center; box-shadow: 0 2px 4px rgba(0,0,0,0.1);
                       margin-bottom: 15px; }
        .metric-box .value { font-size: 2em; font-weight: bold; }
        .metric-box .label { font-size: 0.9em; color: #666; }
        .plot-panel { background: white; border-radius: 8px; padding: 15px;
                       box-shadow: 0 2px 4px rgba(0,0,0,0.1); margin-bottom: 15px; }
        .progress-outer { background: #ddd; border-radius: 8px; height: 13px;
                          overflow: hidden; margin-top: 5px; }
        .progress-inner { background: #ec0016; height: 100%; border-radius: 8px;
                          transition: width 0.5s; }
        .stop-table { width: 100%; border-collapse: collapse; font-size: 0.85em; }
        .stop-table th { background: #ec0016; color: white; padding: 6px 8px;
                         text-align: left; }
        .stop-table td { padding: 5px 8px; border-bottom: 1px solid #eee; }
        .stop-table tr.passed td { color: #999; }
        .stop-table tr.current td { font-weight: bold; background: #fff3cd; }
        .stop-table tr.future td { color: #333; }
        .delay-pos { color: #ec0016; font-weight: bold; }
        .delay-zero { color: #309700; }
      "))
    ),
    shiny::div(class = "header",
      shiny::h2("ICE Portal Data Dashboard"),
      shiny::textOutput("train_info", inline = TRUE)
    ),
    shiny::fluidRow(
      shiny::column(2, shiny::div(class = "metric-box",
        shiny::div(class = "value", style = "color: #ec0016;",
                   shiny::textOutput("current_speed")),
        shiny::div(class = "label", "Speed (km/h)")
      )),
      shiny::column(2, shiny::div(class = "metric-box",
        shiny::div(class = "value", style = "color: #006db6;",
                   shiny::textOutput("avg_speed")),
        shiny::div(class = "label", "Avg Speed (km/h)")
      )),
      shiny::column(4, shiny::div(class = "metric-box",
        shiny::uiOutput("trip_progress"),
        shiny::div(class = "label", "Trip Progress")
      )),
      shiny::column(2, shiny::div(class = "metric-box",
        shiny::div(class = "value", shiny::uiOutput("current_delay")),
        shiny::div(class = "label", "Delay")
      )),
      shiny::column(2, shiny::div(class = "metric-box",
        shiny::div(class = "value", shiny::uiOutput("current_internet")),
        shiny::div(class = "label", "Internet")
      ))
    ),
    shiny::fluidRow(
      shiny::column(12, shiny::div(class = "plot-panel",
        shiny::h4("Speed Over Time"),
        shiny::plotOutput("speed_plot", height = "250px")
      ))
    ),
    shiny::fluidRow(
      shiny::column(12, shiny::div(class = "plot-panel",
        shiny::h4("Acceleration Over Time"),
        shiny::plotOutput("accel_plot", height = "250px")
      ))
    ),
    shiny::fluidRow(
      shiny::column(6, shiny::div(class = "plot-panel",
        shiny::h4("Speed Distribution"),
        shiny::plotOutput("speed_hist", height = "250px")
      )),
      shiny::column(6, shiny::div(class = "plot-panel",
        shiny::h4("Acceleration Distribution"),
        shiny::plotOutput("accel_hist", height = "250px")
      ))
    ),
    shiny::fluidRow(
      shiny::column(6, shiny::div(class = "plot-panel",
        shiny::h4("Internet Connectivity Over Time"),
        shiny::plotOutput("connectivity_plot", height = "250px")
      )),
      shiny::column(6, shiny::div(class = "plot-panel",
        shiny::h4("Connectivity Remaining Time"),
        shiny::plotOutput("remaining_time_plot", height = "250px")
      ))
    ),
    shiny::fluidRow(
      shiny::column(6, shiny::div(class = "plot-panel",
        shiny::h4("Route (Zoomed)"),
        shiny::plotOutput("route_plot_zoom", height = "400px")
      )),
      shiny::column(6, shiny::div(class = "plot-panel",
        shiny::h4("Route (Germany)"),
        shiny::plotOutput("route_plot_full", height = "400px")
      ))
    ),
    shiny::fluidRow(
      shiny::column(6, shiny::div(class = "plot-panel",
        shiny::h4("Delay by Stop"),
        shiny::plotOutput("delay_plot", height = "300px")
      )),
      shiny::column(6, shiny::div(class = "plot-panel",
        shiny::h4(shiny::textOutput("next_stop_heading", inline = TRUE)),
        shiny::uiOutput("delay_reasons_ui")
      ))
    ),
    shiny::fluidRow(
      shiny::column(12, shiny::div(class = "plot-panel",
        shiny::h4("Stops"),
        shiny::uiOutput("stops_table")
      ))
    ),
    shiny::hr(),
    shiny::fluidRow(
      shiny::column(12,
        shiny::em(paste0("Polling every ", poll_interval_sec, " seconds. "),
                  shiny::textOutput("last_update", inline = TRUE))
      )
    )
  )

  server <- function(input, output, session) {
    # Reactive values to accumulate time series
    ts_data <- shiny::reactiveVal(
      data.frame(
        time = as.POSIXct(character()),
        speed = numeric(),
        latitude = numeric(),
        longitude = numeric(),
        internet = character(),
        gps_status = character(),
        connectivity_state = character(),
        connectivity_next = character(),
        connectivity_remaining_sec = numeric(),
        service_level = character(),
        wagon_class = character(),
        stringsAsFactors = FALSE
      )
    )

    # Poll the status API
    poll_result <- shiny::reactivePoll(
      intervalMillis = poll_interval_sec * 1000,
      session = session,
      checkFunc = function() Sys.time(),
      valueFunc = function() {
        tryCatch({
          resp <- httr::GET(
            "https://iceportal.de/api1/rs/status",
            httr::timeout(poll_interval_sec)
          )
          if (httr::status_code(resp) == 200) {
            jsonlite::fromJSON(httr::content(resp, as = "text", encoding = "UTF-8"))
          } else {
            NULL
          }
        }, error = function(e) NULL)
      }
    )

    # Poll the trip API
    trip_result <- shiny::reactivePoll(
      intervalMillis = poll_interval_sec * 1000,
      session = session,
      checkFunc = function() Sys.time(),
      valueFunc = function() {
        tryCatch({
          resp <- httr::GET(
            "https://iceportal.de/api1/rs/tripInfo/trip",
            httr::timeout(poll_interval_sec)
          )
          if (httr::status_code(resp) == 200) {
            jsonlite::fromJSON(httr::content(resp, as = "text", encoding = "UTF-8"))
          } else {
            NULL
          }
        }, error = function(e) NULL)
      }
    )

    # Parse stops from trip data into a data.frame
    parsed_stops <- shiny::reactive({
      tr <- trip_result()
      if (is.null(tr) || is.null(tr$trip) || is.null(tr$trip$stops)) return(NULL)
      stops <- tr$trip$stops
      n <- length(stops$station$name)
      if (n == 0) return(NULL)

      ms_to_posix <- function(x) {
        x <- as.numeric(x)
        ifelse(is.na(x), NA, x / 1000)
      }

      data.frame(
        name = stops$station$name,
        lat = as.numeric(stops$station$geocoordinates$latitude),
        lon = as.numeric(stops$station$geocoordinates$longitude),
        sched_arr = as.POSIXct(ms_to_posix(stops$timetable$scheduledArrivalTime),
                               origin = "1970-01-01", tz = "Europe/Berlin"),
        actual_arr = as.POSIXct(ms_to_posix(stops$timetable$actualArrivalTime),
                                origin = "1970-01-01", tz = "Europe/Berlin"),
        arr_delay = stops$timetable$arrivalDelay,
        sched_dep = as.POSIXct(ms_to_posix(stops$timetable$scheduledDepartureTime),
                               origin = "1970-01-01", tz = "Europe/Berlin"),
        actual_dep = as.POSIXct(ms_to_posix(stops$timetable$actualDepartureTime),
                                origin = "1970-01-01", tz = "Europe/Berlin"),
        dep_delay = stops$timetable$departureDelay,
        track_sched = stops$track$scheduled,
        track_actual = stops$track$actual,
        position_status = stops$info$positionStatus,
        stringsAsFactors = FALSE
      )
    })

    # Extract delay reasons
    delay_reasons <- shiny::reactive({
      tr <- trip_result()
      if (is.null(tr) || is.null(tr$trip) || is.null(tr$trip$stops)) return(NULL)
      stops <- tr$trip$stops
      reasons <- stops$delayReasons
      names_vec <- stops$station$name
      out <- list()
      for (i in seq_along(reasons)) {
        r <- reasons[[i]]
        if (!is.null(r) && is.data.frame(r) && nrow(r) > 0) {
          r$station <- names_vec[i]
          out[[length(out) + 1]] <- r
        }
      }
      if (length(out) == 0) return(NULL)
      do.call(rbind, out)
    })

    # Append new data point whenever poll returns
    shiny::observeEvent(poll_result(), {
      d <- poll_result()
      if (is.null(d)) return()

      conn_state <- NA_character_
      conn_next <- NA_character_
      conn_remaining <- NA_real_
      if (!is.null(d$connectivity)) {
        conn_state <- d$connectivity$currentState %||% NA_character_
        conn_next <- d$connectivity$nextState %||% NA_character_
        conn_remaining <- as.numeric(d$connectivity$remainingTimeSeconds %||% NA_real_)
      }

      new_row <- data.frame(
        time = Sys.time(),
        speed = as.numeric(d$speed %||% NA_real_),
        latitude = as.numeric(d$latitude %||% NA_real_),
        longitude = as.numeric(d$longitude %||% NA_real_),
        internet = as.character(d$internet %||% NA_character_),
        gps_status = as.character(d$gpsStatus %||% NA_character_),
        connectivity_state = conn_state,
        connectivity_next = conn_next,
        connectivity_remaining_sec = conn_remaining,
        service_level = as.character(d$serviceLevel %||% NA_character_),
        wagon_class = as.character(d$wagonClass %||% NA_character_),
        stringsAsFactors = FALSE
      )
      ts_data(rbind(ts_data(), new_row))
    })

    # Derived: speed change (acceleration) in km/h per second
    accel_data <- shiny::reactive({
      df <- ts_data()
      if (nrow(df) < 2) return(NULL)
      dt_sec <- as.numeric(difftime(df$time[-1], df$time[-nrow(df)],
                                    units = "secs"))
      dv <- diff(df$speed)
      # Avoid division by zero for duplicate timestamps
      dt_sec[dt_sec == 0] <- NA_real_
      accel_kmh_s <- dv / dt_sec
      data.frame(
        time = df$time[-1],
        accel_kmh_s = accel_kmh_s,
        accel_ms2 = accel_kmh_s / 3.6,
        stringsAsFactors = FALSE
      )
    })

    # ---- Metric outputs ----
    output$train_info <- shiny::renderText({
      d <- poll_result()
      tr <- trip_result()
      if (is.null(d) && is.null(tr)) return("Waiting for data...")
      train_label <- if (!is.null(tr) && !is.null(tr$trip)) {
        paste0(tr$trip$journeyDisplayValue %||% (paste0(d$trainType %||% "?", " ", d$tzn %||% "")))
      } else {
        paste0(d$trainType %||% "?", " ", d$tzn %||% "")
      }
      dest <- if (!is.null(tr) && !is.null(tr$trip$stopInfo$finalStationName)) {
        paste0(" \u2192 ", tr$trip$stopInfo$finalStationName)
      } else ""
      class_info <- if (!is.null(d)) paste0(" | Class: ", d$wagonClass %||% "?") else ""
      paste0(train_label, dest, class_info)
    })

    output$current_speed <- shiny::renderText({
      d <- poll_result()
      if (is.null(d) || is.null(d$speed)) return("--")
      format(round(d$speed, 1), nsmall = 1)
    })

    output$current_internet <- shiny::renderUI({
      d <- poll_result()
      if (is.null(d) || is.null(d$internet)) {
        return(shiny::tags$span(style = "color: #999999;", "--"))
      }
      shiny::tags$span(
        style = paste0("color: ", internet_color(d$internet), ";"),
        d$internet
      )
    })

    output$avg_speed <- shiny::renderText({
      df <- ts_data()
      if (nrow(df) < 1) return("--")
      format(round(mean(df$speed, na.rm = TRUE), 1), nsmall = 1)
    })

    output$current_delay <- shiny::renderUI({
      sp <- parsed_stops()
      if (is.null(sp)) return(shiny::tags$span(style = "color: #999;", "--"))
      # Find the next upcoming stop
      future <- sp[sp$position_status %in% c("future"), ]
      departed <- sp[sp$position_status == "departed", ]
      current <- if (nrow(departed) > 0) departed[nrow(departed), ] else if (nrow(future) > 0) future[1, ] else NULL
      if (is.null(current)) return(shiny::tags$span(style = "color: #309700;", "0 min"))
      delay_str <- current$arr_delay
      if (is.null(delay_str) || is.na(delay_str) || delay_str == "") {
        delay_str <- current$dep_delay
      }
      if (is.null(delay_str) || is.na(delay_str) || delay_str == "") {
        return(shiny::tags$span(style = "color: #309700;", "0 min"))
      }
      delay_min <- suppressWarnings(as.numeric(gsub("[^0-9-]", "", delay_str)))
      if (is.na(delay_min)) return(shiny::tags$span(style = "color: #309700;", "0 min"))
      clr <- if (delay_min > 0) "#ec0016" else "#309700"
      shiny::tags$span(style = paste0("color: ", clr, ";"),
                       paste0(ifelse(delay_min > 0, "+", ""), delay_min, " min"))
    })

    output$next_stop_heading <- shiny::renderText({
      sp <- parsed_stops()
      if (is.null(sp)) return("Next Stop")
      future <- sp[sp$position_status == "future", ]
      next_name <- if (nrow(future) == 0) "Arrived" else future$name[1]
      paste0("Next: ", next_name)
    })

    output$trip_progress <- shiny::renderUI({
      tr <- trip_result()
      if (is.null(tr) || is.null(tr$trip)) {
        return(shiny::div(class = "value", style = "color: #999;", "--"))
      }
      total <- as.numeric(tr$trip$totalDistance %||% 1)
      base_pos <- as.numeric(tr$trip$actualPosition %||% 0)
      dist_from_last <- as.numeric(tr$trip$distanceFromLastStop %||% 0)
      pos <- base_pos + dist_from_last
      pct <- min(100, round(pos / total * 100))
      shiny::tagList(
        shiny::div(class = "value", style = "color: #ec0016; font-size: 1.1em;",
                   paste0(pct, "%")),
        shiny::div(class = "progress-outer",
          shiny::div(class = "progress-inner",
                     style = paste0("width: ", pct, "%;"))
        )
      )
    })

    output$last_update <- shiny::renderText({
      df <- ts_data()
      if (nrow(df) == 0) return("")
      paste0("Last update: ", format(max(df$time), "%H:%M:%S"))
    })

    # ---- Plots ----
    output$speed_plot <- shiny::renderPlot({
      df <- ts_data()
      if (nrow(df) < 1) return(NULL)
      ggplot2::ggplot(df, ggplot2::aes(x = time, y = speed)) +
        ggplot2::geom_line(color = "#ec0016", linewidth = 1) +
        ggplot2::geom_point(color = "#ec0016", size = 2) +
        ggplot2::expand_limits(y = 0) +
        ggplot2::labs(x = "Time", y = "Speed (km/h)") +
        ggplot2::theme_minimal() +
        ggplot2::theme(text = ggplot2::element_text(size = 13))
    })

    output$accel_plot <- shiny::renderPlot({
      ad <- accel_data()
      if (is.null(ad)) return(NULL)
      ad$direction <- ifelse(ad$accel_ms2 >= 0, "Accelerating", "Decelerating")
      ggplot2::ggplot(ad, ggplot2::aes(x = time, y = accel_ms2,
                                       fill = direction)) +
        ggplot2::geom_col(width = poll_interval_sec * 0.8) +
        ggplot2::geom_hline(yintercept = 0, linewidth = 0.3) +
        ggplot2::scale_fill_manual(
          values = c("Accelerating" = "#309700", "Decelerating" = "#ec0016")
        ) +
        ggplot2::labs(x = "Time",
                      y = expression("Acceleration (m/s"^2*")"),
                      fill = NULL) +
        ggplot2::theme_minimal() +
        ggplot2::theme(text = ggplot2::element_text(size = 13),
                       legend.position = "bottom")
    })

    output$speed_hist <- shiny::renderPlot({
      df <- ts_data()
      if (nrow(df) < 2) return(NULL)
      nbins <- round(max(1, min(nrow(df) / 3, sqrt(nrow(df)))))
      ggplot2::ggplot(df, ggplot2::aes(x = speed)) +
        ggplot2::geom_histogram(fill = "#ec0016", color = "white",
                                bins = nbins) +
        ggplot2::labs(x = "Speed (km/h)", y = "Count") +
        ggplot2::theme_minimal() +
        ggplot2::theme(text = ggplot2::element_text(size = 13))
    })

    output$accel_hist <- shiny::renderPlot({
      ad <- accel_data()
      if (is.null(ad) || nrow(ad) < 2) return(NULL)
      nbins <- round(max(1, min(nrow(ad) / 3, sqrt(nrow(ad)))))
      ggplot2::ggplot(ad, ggplot2::aes(x = accel_ms2)) +
        ggplot2::geom_histogram(fill = "#006db6", color = "white",
                                bins = nbins) +
        ggplot2::geom_vline(xintercept = 0, linetype = "dashed", color = "#333") +
        ggplot2::labs(x = expression("Acceleration (m/s"^2*")"), y = "Count") +
        ggplot2::theme_minimal() +
        ggplot2::theme(text = ggplot2::element_text(size = 13))
    })

    output$connectivity_plot <- shiny::renderPlot({
      df <- ts_data()
      if (nrow(df) < 1) return(NULL)
      internet_levels <- c("NO_INFO", "UNSTABLE", "WEAK", "MIDDLE", "HIGH")
      df$internet_num <- match(df$internet, internet_levels)
      ggplot2::ggplot(df, ggplot2::aes(x = time, y = internet_num)) +
        ggplot2::geom_step(color = "#1b1b1b", linewidth = 1) +
        ggplot2::scale_y_continuous(
          breaks = seq_along(internet_levels),
          labels = internet_levels,
          limits = c(1, length(internet_levels))
        ) +
        ggplot2::labs(x = "Time", y = "Internet Quality") +
        ggplot2::theme_minimal() +
        ggplot2::theme(text = ggplot2::element_text(size = 13))
    })

    output$remaining_time_plot <- shiny::renderPlot({
      df <- ts_data()
      if (nrow(df) < 1 || all(is.na(df$connectivity_remaining_sec))) return(NULL)
      df$remaining_min <- df$connectivity_remaining_sec / 60
      ggplot2::ggplot(df, ggplot2::aes(x = time, y = remaining_min)) +
        ggplot2::geom_line(color = "#309700", linewidth = 1) +
        ggplot2::geom_point(ggplot2::aes(color = connectivity_next), size = 2) +
        ggplot2::labs(x = "Time", y = "Minutes Until Change",
                      color = "Next State") +
        ggplot2::theme_minimal() +
        ggplot2::theme(text = ggplot2::element_text(size = 13),
                       legend.position = "bottom")
    })

    # Helper: station marker layers from trip data
    station_layers <- function() {
      sp <- parsed_stops()
      if (is.null(sp)) return(NULL)
      valid <- !is.na(sp$lon) & !is.na(sp$lat)
      sp <- sp[valid, ]
      if (nrow(sp) == 0) return(NULL)
      sp$shape <- ifelse(sp$position_status %in% c("passed", "departed"), 16, 1)
      list(
        ggplot2::geom_point(
          data = sp,
          ggplot2::aes(x = lon, y = lat),
          shape = sp$shape, size = 3, color = "#333"
        ),
        ggrepel::geom_text_repel(
          data = sp,
          ggplot2::aes(x = lon, y = lat, label = name),
          size = 2.8, color = "#333",
          max.overlaps = 20,
          segment.color = "#999",
          segment.size = 0.3,
          min.segment.length = 0.2,
          box.padding = 0.3
        )
      )
    }

    # Helper to build actual route layers (data on top)
    route_layers <- function(df) {
      speed_max <- max(300, max(df$speed, na.rm = TRUE))
      list(
        ggplot2::geom_path(
          data = df,
          ggplot2::aes(x = longitude, y = latitude),
          color = "#ec0016", linewidth = 1.2
        ),
        ggplot2::geom_point(
          data = df,
          ggplot2::aes(x = longitude, y = latitude, color = speed),
          size = 2.5
        ),
        ggplot2::scale_color_viridis_c(
          name = "Speed\n(km/h)", option = "C",
          limits = c(0, speed_max)
        ),
        ggplot2::labs(x = "Longitude", y = "Latitude"),
        ggplot2::theme_minimal(),
        ggplot2::theme(text = ggplot2::element_text(size = 13))
      )
    }

    output$route_plot_zoom <- shiny::renderPlot({
      df <- ts_data()
      if (nrow(df) < 1) return(NULL)
      valid <- !is.na(df$longitude) & !is.na(df$latitude)
      if (sum(valid) < 1) return(NULL)
      df <- df[valid, ]

      ggplot2::ggplot() +
        station_layers() +
        route_layers(df) +
        ggplot2::coord_sf(
          xlim = range(df$longitude) + c(-0.5, 0.5),
          ylim = range(df$latitude) + c(-0.25, 0.25),
          crs = 4326
        )
    })

    output$route_plot_full <- shiny::renderPlot({
      df <- ts_data()
      if (nrow(df) < 1) return(NULL)
      valid <- !is.na(df$longitude) & !is.na(df$latitude)
      if (sum(valid) < 1) return(NULL)
      df <- df[valid, ]

      p <- ggplot2::ggplot()
      if (!is.null(de_geom)) {
        p <- p + ggplot2::geom_sf(
          data = de_geom, fill = "grey90", color = "grey70"
        )
      }
      p + station_layers() +
        route_layers(df) +
        ggplot2::coord_sf(
          xlim = c(5.8, 15.1), ylim = c(47.2, 55.1), crs = 4326
        )
    })

    # ---- Trip outputs ----
    output$delay_plot <- shiny::renderPlot({
      sp <- parsed_stops()
      if (is.null(sp)) return(NULL)
      sp$arr_delay_min <- suppressWarnings(
        as.numeric(gsub("[^0-9.-]", "", sp$arr_delay))
      )
      sp$arr_delay_min[is.na(sp$arr_delay_min)] <- 0
      sp$name <- factor(sp$name, levels = sp$name)
      sp$status <- ifelse(sp$position_status %in% c("passed", "departed"),
                          "Passed", "Upcoming")
      ggplot2::ggplot(sp, ggplot2::aes(x = name, y = arr_delay_min,
                                       fill = status)) +
        ggplot2::geom_col() +
        ggplot2::geom_hline(yintercept = 0, linewidth = 0.3) +
        ggplot2::scale_fill_manual(
          values = c("Passed" = "#ec0016", "Upcoming" = "#ffaaaa")
        ) +
        ggplot2::labs(x = NULL, y = "Arrival Delay (min)", fill = NULL) +
        ggplot2::theme_minimal() +
        ggplot2::theme(
          text = ggplot2::element_text(size = 12),
          axis.text.x = ggplot2::element_text(angle = 35, hjust = 1),
          legend.position = "bottom"
        )
    })

    output$delay_reasons_ui <- shiny::renderUI({
      dr <- delay_reasons()
      if (is.null(dr) || nrow(dr) == 0) {
        return(NULL)
      }
      # Deduplicate: unique reason text with affected stations
      agg <- aggregate(station ~ text, data = dr, FUN = function(x) {
        paste(unique(x), collapse = ", ")
      })
      items <- lapply(seq_len(nrow(agg)), function(i) {
        shiny::tags$li(
          shiny::strong(agg$text[i]),
          shiny::br(),
          shiny::tags$small(style = "color: #666;",
                           paste0("Affects: ", agg$station[i]))
        )
      })
      shiny::tagList(
        shiny::tags$hr(style = "margin: 15px 0;"),
        shiny::tags$h5("Delay Reasons"),
        shiny::tags$ul(style = "padding-left: 18px;", items)
      )
    })

    output$stops_table <- shiny::renderUI({
      sp <- parsed_stops()
      if (is.null(sp)) return(shiny::p(shiny::em("No trip data yet.")))

      fmt_time <- function(t) {
        ifelse(is.na(t), "", format(t, "%H:%M"))
      }
      fmt_delay <- function(d) {
        if (is.null(d) || is.na(d) || d == "") return("")
        val <- suppressWarnings(as.numeric(gsub("[^0-9.-]", "", d)))
        if (is.na(val) || val == 0) {
          as.character(shiny::tags$span(class = "delay-zero", "0"))
        } else {
          as.character(shiny::tags$span(class = "delay-pos",
                                        paste0("+", val)))
        }
      }
      fmt_stay <- function(arr, dep) {
        if (is.na(arr) || is.na(dep)) return("")
        mins <- as.numeric(difftime(dep, arr, units = "mins"))
        if (is.na(mins) || mins < 0) return("")
        paste0(round(mins), " min")
      }

      header <- shiny::tags$tr(
        shiny::tags$th("Station"),
        shiny::tags$th("Arr (sched)"),
        shiny::tags$th("Arr (actual)"),
        shiny::tags$th("Delay"),
        shiny::tags$th("Dep (sched)"),
        shiny::tags$th("Dep (actual)"),
        shiny::tags$th("Delay"),
        shiny::tags$th("Stay (sched)"),
        shiny::tags$th("Stay (actual)"),
        shiny::tags$th("Track")
      )

      rows <- lapply(seq_len(nrow(sp)), function(i) {
        row_class <- switch(sp$position_status[i],
          "passed" = "passed", "departed" = "current", "future" = "future",
          "")
        track_str <- if (!is.na(sp$track_actual[i]) && sp$track_actual[i] != sp$track_sched[i]) {
          paste0(sp$track_actual[i], " (", sp$track_sched[i], ")")
        } else {
          sp$track_sched[i] %||% ""
        }
        shiny::tags$tr(class = row_class,
          shiny::tags$td(sp$name[i]),
          shiny::tags$td(fmt_time(sp$sched_arr[i])),
          shiny::tags$td(fmt_time(sp$actual_arr[i])),
          shiny::tags$td(shiny::HTML(fmt_delay(sp$arr_delay[i]))),
          shiny::tags$td(fmt_time(sp$sched_dep[i])),
          shiny::tags$td(fmt_time(sp$actual_dep[i])),
          shiny::tags$td(shiny::HTML(fmt_delay(sp$dep_delay[i]))),
          shiny::tags$td(fmt_stay(sp$sched_arr[i], sp$sched_dep[i])),
          shiny::tags$td(fmt_stay(sp$actual_arr[i], sp$actual_dep[i])),
          shiny::tags$td(track_str)
        )
      })

      shiny::tags$table(class = "stop-table",
        shiny::tags$thead(header),
        shiny::tags$tbody(rows)
      )
    })
  }

  shiny::shinyApp(ui = ui, server = server)
}

# Null-coalescing operator (not exported)
`%||%` <- function(x, y) if (is.null(x)) y else x
