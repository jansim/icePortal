\name{launch_dashboard}
\alias{launch_dashboard}
\title{Launch ICE Train Status Dashboard}
\usage{
launch_dashboard(poll_interval_sec = 10, ...)
}
\arguments{
  \item{poll_interval_sec}{Polling interval in seconds (default: 10).}
  \item{...}{Additional arguments passed to \code{\link[shiny]{runApp}}.}
}
\description{
Starts a Shiny app that periodically queries the Deutsche Bahn ICE Portal
API (\url{https://iceportal.de/api1/rs/status}) and displays real-time time
series plots of train status data including speed, internet connectivity,
GPS coordinates, and more.
}
\examples{
\dontrun{
launch_dashboard()
launch_dashboard(poll_interval_sec = 5)
}
}
