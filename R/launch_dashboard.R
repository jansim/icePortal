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

#' Build the Shiny app object (without launching)
#'
#' @param poll_interval_sec Polling interval in seconds.
#' @return A Shiny app object.
#' @keywords internal
build_app <- function(poll_interval_sec = 10) {

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
        .metric-box .value { font-size: 2em; font-weight: bold; color: #ec0016; }
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
        shiny::div(class = "value", shiny::textOutput("current_speed")),
        shiny::div(class = "label", "Speed (km/h)")
      )),
      shiny::column(3, shiny::div(class = "metric-box",
        shiny::div(class = "value", shiny::textOutput("current_internet")),
        shiny::div(class = "label", "Internet Quality")
      )),
      shiny::column(3, shiny::div(class = "metric-box",
        shiny::div(class = "value", shiny::textOutput("current_gps")),
        shiny::div(class = "label", "GPS Status")
      )),
      shiny::column(3, shiny::div(class = "metric-box",
        shiny::div(class = "value", shiny::textOutput("n_samples")),
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
      shiny::column(6, shiny::div(class = "plot-panel",
        shiny::h4("Speed Distribution"),
        shiny::plotOutput("speed_hist", height = "250px")
      )),
      shiny::column(6, shiny::div(class = "plot-panel",
        shiny::h4("Internet Connectivity Over Time"),
        shiny::plotOutput("connectivity_plot", height = "250px")
      ))
    ),
    shiny::fluidRow(
      shiny::column(6, shiny::div(class = "plot-panel",
        shiny::h4("Latitude & Longitude Over Time"),
        shiny::plotOutput("coords_plot", height = "250px")
      )),
      shiny::column(6, shiny::div(class = "plot-panel",
        shiny::h4("Connectivity Remaining Time"),
        shiny::plotOutput("remaining_time_plot", height = "250px")
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

    output$current_internet <- shiny::renderText({
      d <- poll_result()
      if (is.null(d) || is.null(d$internet)) return("--")
      d$internet
    })

    output$current_gps <- shiny::renderText({
      d <- poll_result()
      if (is.null(d) || is.null(d$gpsStatus)) return("--")
      d$gpsStatus
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
        ggplot2::labs(x = "Time", y = "Speed (km/h)") +
        ggplot2::theme_minimal() +
        ggplot2::theme(text = ggplot2::element_text(size = 13))
    })

    output$speed_hist <- shiny::renderPlot({
      df <- ts_data()
      if (nrow(df) < 2) return(NULL)
      ggplot2::ggplot(df, ggplot2::aes(x = speed)) +
        ggplot2::geom_histogram(fill = "#ec0016", color = "white",
                                bins = max(5, min(30, nrow(df) / 2))) +
        ggplot2::labs(x = "Speed (km/h)", y = "Count") +
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
        ggplot2::geom_point(color = "#1b1b1b", size = 2) +
        ggplot2::scale_y_continuous(
          breaks = seq_along(internet_levels),
          labels = internet_levels,
          limits = c(1, length(internet_levels))
        ) +
        ggplot2::labs(x = "Time", y = "Internet Quality") +
        ggplot2::theme_minimal() +
        ggplot2::theme(text = ggplot2::element_text(size = 13))
    })

    output$coords_plot <- shiny::renderPlot({
      df <- ts_data()
      if (nrow(df) < 1) return(NULL)
      # Normalize lat/lon to 0-1 range for dual-axis display
      lat_rng <- range(df$latitude, na.rm = TRUE)
      lon_rng <- range(df$longitude, na.rm = TRUE)
      ggplot2::ggplot(df, ggplot2::aes(x = time)) +
        ggplot2::geom_line(ggplot2::aes(y = latitude, color = "Latitude"),
                           linewidth = 1) +
        ggplot2::geom_line(ggplot2::aes(y = longitude, color = "Longitude"),
                           linewidth = 1, linetype = "dashed") +
        ggplot2::scale_color_manual(values = c("Latitude" = "#006db6",
                                               "Longitude" = "#ec0016")) +
        ggplot2::labs(x = "Time", y = "Degrees", color = NULL) +
        ggplot2::theme_minimal() +
        ggplot2::theme(text = ggplot2::element_text(size = 13),
                       legend.position = "bottom")
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
  }

  shiny::shinyApp(ui = ui, server = server)
}

# Null-coalescing operator (not exported)
`%||%` <- function(x, y) if (is.null(x)) y else x
