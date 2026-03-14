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
      "))
    ),
    shiny::div(class = "header",
      shiny::h2("ICE Train Status Dashboard"),
      shiny::textOutput("train_info", inline = TRUE)
    ),
    shiny::fluidRow(
      shiny::column(3, shiny::div(class = "metric-box",
        shiny::div(class = "value", style = "color: #ec0016;",
                   shiny::textOutput("current_speed")),
        shiny::div(class = "label", "Speed (km/h)")
      )),
      shiny::column(3, shiny::div(class = "metric-box",
        shiny::div(class = "value", shiny::uiOutput("current_internet")),
        shiny::div(class = "label", "Internet Quality")
      )),
      shiny::column(3, shiny::div(class = "metric-box",
        shiny::div(class = "value", shiny::uiOutput("current_gps")),
        shiny::div(class = "label", "GPS Status")
      )),
      shiny::column(3, shiny::div(class = "metric-box",
        shiny::div(class = "value", style = "color: #ec0016;",
                   shiny::textOutput("n_samples")),
        shiny::div(class = "label", "Data Points")
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

    # Poll the API
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
      if (is.null(d)) return("Waiting for data...")
      paste0(d$trainType %||% "?", " ", d$tzn %||% "",
             " | Class: ", d$wagonClass %||% "?")
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

    output$current_gps <- shiny::renderUI({
      d <- poll_result()
      if (is.null(d) || is.null(d$gpsStatus)) {
        return(shiny::tags$span(style = "color: #999999;", "--"))
      }
      shiny::tags$span(
        style = paste0("color: ", gps_color(d$gpsStatus), ";"),
        d$gpsStatus
      )
    })

    output$n_samples <- shiny::renderText({
      nrow(ts_data())
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

    # Helper to build route layers
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
      p + route_layers(df) +
        ggplot2::coord_sf(
          xlim = c(5.8, 15.1), ylim = c(47.2, 55.1), crs = 4326
        )
    })
  }

  shiny::shinyApp(ui = ui, server = server)
}

# Null-coalescing operator (not exported)
`%||%` <- function(x, y) if (is.null(x)) y else x
