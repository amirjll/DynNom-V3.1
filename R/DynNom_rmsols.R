if (getRversion() >= "2.15.1") utils::globalVariables(c("counter", "Prediction", "input.data", "old.d"))

DynNom.ols <- function(model, data,
                       clevel = 0.95, covariate = c("slider", "numeric")) {

  data <- data.frame(data)
  model <- update(model,x=T,y=T)

  if (length(dim(data)) > 2)
    stop("Error in data format: dataframe format required")

  if(length(class(model$y))==1){
    if (class(model$y)[1] == "logical")  stop("Error in model syntax: logical form for response not supported")} else{
      if (class(model$y)[2] == "logical")  stop("Error in model syntax: logical form for response not supported")
    }

  vars=c()
  for(i in 1:length(model$Design$name)){
    if(model$Design$assume[i]!="interaction") vars[i] <- as.character(model$Design$name[i]) else vars[i]="inter"
  }
  
  vars <- subset(vars,vars!="inter")
  vars <- as.character(c(model$terms[[2]],vars))

  cl.vars <-  model$Design$assume[model$Design$assume!="interaction"]

  cvars <- NULL
  cvars[1] <- class(model$y)
  for(i in 2:length(vars))  cvars[i]=cl.vars[i-1]

  covariate <- match.arg(covariate)
  input.data <- NULL
  old.d <- NULL

  runApp(list(

    ui = bootstrapPage(fluidPage(
      titlePanel("Dynamic Nomogram"),
      sidebarLayout(sidebarPanel(uiOutput("manySliders.f"),
                                 uiOutput("manySliders.n"),
                                 checkboxInput("limits", "Set x-axis ranges"),
                                 conditionalPanel(condition = "input.limits == true",
                                                  numericInput("uxlim", "x-axis lower", NA),
                                                  numericInput("lxlim", "x-axis upper", NA)),
                                 actionButton("add", "Predict"),
                                 br(), br(),
                                 helpText("Press Quit to exit the application"),
                                 actionButton("quit", "Quit")
      ),
      mainPanel(tabsetPanel(id = "tabs",
                            tabPanel("Graphical Summary", plotOutput("plot")),
                            tabPanel("Numerical Summary", verbatimTextOutput("data.pred")),
                            tabPanel("Model Summary", verbatimTextOutput("summary"))
      )
      )
      ))),

    server = function(input, output){

      q <- observe({
        if (input$quit == 1)
          stopApp()
      })

      limits0 <- c(mean(as.numeric(model$y)) - 3 * sd(model$y),
                   mean(as.numeric(model$y)) + 3 * sd(model$y))
      limits <- reactive({
        if (as.numeric(input$limits) == 1) {
          limits <- c(input$lxlim, input$uxlim)
        } else {
          limits <- limits0
        }
      })

      neededVar <- vars[-1]
      data <- cbind(resp=model$y,na.omit(data[, neededVar]))
      data <- as.data.frame(data)
      colnames(data) <- c("resp",neededVar)
      input.data <<- data[1, ]
      input.data[1, ] <<- NA

      b <- 1
      i.factor <- NULL
      i.numeric <- NULL
      for (j in 2:length(vars)) {
        for (i in 1:length(data)) {
          if (vars[j] == names(data)[i]) {
            if (cvars[j] == "category" |
                cvars[j] == "scored"|
                cvars[j] == "factor"|
                cvars[j] == "ordered") {
              i.factor <- rbind(i.factor, c(vars[j], j, i, b))
              (break)()
            }
            if (cvars[j] == "rcspline"|
                cvars[j] == "asis"|
                cvars[j] == "lspline"|
                cvars[j] == "polynomial"|
                cvars[j] == "numeric" |
                cvars[j] == "integer"|
                cvars[j] == "double"|
                cvars[j] == "matrx") {
              i.numeric <- rbind(i.numeric, c(vars[j], j, i))
              b <- b + 1
              (break)()
            }
          }
        }
      }

      nn <- nrow(i.numeric)
      if (is.null(nn)) {
        nn <- 0
      }
      nf <- nrow(i.factor)
      if (is.null(nf)) {
        nf <- 0
      }

      if (nf > 0) {
        output$manySliders.f <- renderUI({
          slide.bars <- list(lapply(1:nf, function(j) {
            selectInput(paste("factor", j, sep = ""),
                        vars[as.numeric(i.factor[j, 2])],
                        model$Design$parms[[i.factor[j,1]]], multiple = FALSE)
          }))
          do.call(tagList, slide.bars)
        })
      }

      if (nn > 0) {
        output$manySliders.n <- renderUI({
          if (covariate == "slider") {
            slide.bars <- list(lapply(1:nn, function(j) {
              sliderInput(paste("numeric", j, sep = ""),
                          vars[as.numeric(i.numeric[j, 2])],
                          min = as.integer(min(na.omit(data[, as.numeric(i.numeric[j, 3])]))),
                          max = as.integer(max(na.omit(data[, as.numeric(i.numeric[j, 3])]))) + 1,
                          value = as.integer(mean(na.omit(data[, as.numeric(i.numeric[j, 3])]))))
            }))
          }
          if (covariate == "numeric") {
            slide.bars <- list(lapply(1:nn, function(j) {
              numericInput(paste("numeric", j, sep = ""),
                           vars[as.numeric(i.numeric[j, 2])],
                           value = as.integer(mean(na.omit(data[, as.numeric(i.numeric[j, 3])]))))
            }))
          }
          do.call(tagList, slide.bars)
        })
      }

      a <- 0
      new.d <- reactive({
        if (nf > 0) {
          input.f <- vector("list", nf)
          for (i in 1:nf) {
            input.f[[i]] <- local({
              input[[paste("factor", i, sep = "")]]
            })
            names(input.f)[i] <- i.factor[i, 1]
          }
        }
        if (nn > 0) {
          input.n <- vector("list", nn)
          for (i in 1:nn) {
            input.n[[i]] <- local({
              input[[paste("numeric", i, sep = "")]]
            })
            names(input.n)[i] <- i.numeric[i, 1]
          }
        }
        if (nn == 0) {
          out <- data.frame(do.call("cbind", input.f))
        }
        if (nf == 0) {
          out <- data.frame(do.call("cbind", input.n))
        }
        if (nf > 0 & nn > 0) {
          out <- data.frame(do.call("cbind", input.f), do.call("cbind", input.n))
        }
        if (a == 0) {
          wher <- match(names(out), names(input.data)[-1])
          out <- out[wher]
          input.data <<- rbind(input.data[-1], out)
        }
        if (a > 0) {
          wher <- match(names(out), names(input.data))
          out <- out[wher]
          input.data <<- rbind(input.data, out)
        }
        a <<- a + 1
        out
      })

      p1 <- NULL
      old.d <- NULL
      data2 <- reactive({
        if (input$add == 0)
          return(NULL)
        if (input$add > 0) {
          if (isTRUE(compare(old.d, new.d())) == FALSE) {
            OUT <- isolate({

            if(is.error(try(predict(model, newdata = new.d(), se.fit = TRUE)))==T){
              d.p <- data.frame(Prediction = NA, Lower.bound = NA,
                                Upper.bound = NA)
             } else{
              pred <- predict(model, newdata = new.d(), se.fit = TRUE)
              lwb <- pred$linear.predictors - (qt(1 - (1 - clevel)/2, model$df.residual) * pred$se.fit)
              upb <- pred$linear.predictors + (qt(1 - (1 - clevel)/2, model$df.residual) * pred$se.fit)

              if(is.infinite(round(pred$linear.predictors,digits = 4))){
                d.p <- data.frame(Prediction = NA, Lower.bound = NA,
                                  Upper.bound = NA)
              } else{
                d.p <- data.frame(Prediction = round(pred$linear.predictors,digits = 4),
                                  Lower.bound = round(lwb,digits=4), Upper.bound = round(upb,digits = 4))
              }

              old.d <<- new.d()
              data.p <- cbind(d.p, counter = 1)
              p1 <<- rbind(p1, data.p)
              p1$count <- seq(1, dim(p1)[1])
              p1
            }
            })
          } else {
            p1$count <- seq(1, dim(p1)[1])
            OUT <- p1
          }
        }
        OUT
      })

      output$plot <- renderPlot({
        if (input$add == 0)
          return(NULL)
        OUT <- isolate({
          if (is.null(new.d()))
            return(NULL)

          if (dim(na.omit(data2()))[1]==0 ) return(NULL)

          if (is.na(input$lxlim) | is.na(input$uxlim)) {
            lim <- limits0
          } else {
            lim <- limits()
          }
          yli <- c(0 - 0.5, 10 + 0.5)
          if (dim(input.data)[1] > 11)
            yli <- c(dim(input.data)[1] - 11.5, dim(input.data)[1] - 0.5)
          p <- ggplot(data = data2()[!is.na(data2()$Prediction),], aes(x = Prediction, y = 0:(sum(counter) - 1)))
          p <- p + geom_point(size = 4, colour = data2()$count[!is.na(data2()$Prediction)], shape = 15)
          p <- p + ylim(yli[1], yli[2]) + coord_cartesian(xlim = lim)
          p <- p + geom_errorbarh(xmax = data2()$Upper.bound[!is.na(data2()$Prediction)], xmin = data2()$Lower.bound[!is.na(data2()$Prediction)],
                                  size = 1.45, height = 0.4, colour = data2()$count[!is.na(data2()$Prediction)])
          p <- p + labs(title = paste(clevel * 100, "% ", "Confidence Interval for Response", sep = ""),
                        x = "Response", y = NULL)
          p <- p + theme_bw() + theme(axis.text.y = element_blank(), text = element_text(face = "bold", size = 14))
          print(p)
        })
        OUT
      })

      output$data.pred <- renderPrint({
        if (input$add > 0) {
          OUT <- isolate({
            if (nrow(data2() > 0)) {
              if (dim(input.data)[2] == 1) {
                in.d <- data.frame(input.data[-1, ])
                names(in.d) <- vars[2]
                data.p <- cbind(in.d, data2()[1:3])
                data.p$Prediction[is.na(data.p$Prediction)] <- "Not"
                data.p$Lower.bound[is.na(data.p$Lower.bound)] <- "IN"
                data.p$Upper.bound[is.na(data.p$Upper.bound)] <- "RANGE"
              }
              if (dim(input.data)[2] > 1) {
                data.p <- cbind(input.data[-1, ], data2()[1:3])
                data.p$Prediction[is.na(data.p$Prediction)] <- "Not"
                data.p$Lower.bound[is.na(data.p$Lower.bound)] <- "IN"
                data.p$Upper.bound[is.na(data.p$Upper.bound)] <- "RANGE"
              }
              stargazer(data.p, summary = FALSE, type = "text")
            }
          })
        }
      })

      output$summary <- renderPrint({

        if(is.null(model$stat)==T){
          stargazer(model,type = "text", omit.stat = c("LL", "ser", "f"), ci = TRUE, ci.level = clevel,
                    single.row = TRUE, title = paste("Linear Regression:", model$call[2], sep = " "))

        } else{
          stargazer(model,model$stats, type = "text", omit.stat = c("LL", "ser", "f"), ci = TRUE, ci.level = clevel,
                    single.row = TRUE, title = paste("Linear Regression:", model$call[2], sep = " "))
        }
     })
    }
  )
  )
}
