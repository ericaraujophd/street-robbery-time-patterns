# Crime Data Analysis in Lavras (Brazil)
#### Eric Fernandes de Mello Araújo & Charlotte Gerritsen
###### Universidade Federal de Lavras (Brazil)
###### Vrije Universiteit Amsterdam (The Netherlands)
---

*This material is part of the Chapter 6 of the book "Agent-Based Modelling for Criminological Theory Testing and Development".*

## WHAT IS IT?


This is an initial model for offenders behaviour trying to commit street robberies in a map of Lavras (Brazil). The model is based on routine activity theory and is composed of two types of agents: citizens and offenders.

Citizens are targets for offenders motivated enough to act as a street robbery.

## HOW IT WORKS

The number of people on the streets is a function of the time of the day. For citizens, daylight is when people are in higher number on the streets, while for offenders it is night time.

Each citizen has an awareness value, which indicates how attentious is the agent to threats when walking on the streets. This awareness is random at first, but chances according to the time of the day and the density of the place where the agent is located.

Each offender has a motivation value, which indicates how willing is the agent to commit a crime, in our case, a street robbery. The agent will find favourable to act in case the density of the place is low, and the victim is not aware enough of the danger.

## HOW TO USE IT

SETUP initializes the model. Agents are then created, and placed in one of the vertices. The map is loaded based on an external shapefile from OpenStreetMaps (OSM).

GO runs the model. There are two GO buttons: one that runs one step at a time, and one that runs forever. The procedure will update the time of the day, move the agents using a random-walk algorithm, update the attractiveness of the places and the citizens awareness, before asking the available offenders to decide if they will try to commit a robbery and who is the target.

The switch SHOW-BUILDINGS is used to show the shapefile of the buildings on the map.

The sliders AWARENESS-SF, CRIME-HIST-BALANCE AND MOTIVATION-SF are speed factors used to define how fast awareness, history of crime and offenders' motivation change over time.

The slider NUM-PEOPLE defines the total number of citizens to be created.

The slider NUM-OFFENDERS defines how many offenders will be created in total.

The sliders CRIME-HIST-SF, ATTRACTIVENESS-SF AND VICTIM-HISTORY-SF are speed factors not used for this specific simulation, but incorporated for further studies.

The plot DENSITY shows the density of people on the streets according to the time.

The plot CRIMES PER HOUR show a histogram of the number of crimes for each one hour window slot.

The plot ENVORNMENTAL VARIABLES shows how variables Lighting and Attractiveness change over time throughout the simulation.

The monitor PEOPLE ON THE STREETS shows the number of citizens on the streets in each time of the day.

The monitor TOTAL CRIMES shows the total number of crimes committed during the simulation.

The monitors WEEKDAY, DAY, HOUR and MIN show how the ticks converte to real time during the day. Every tick is 10 minutes in real time.

The switch GRAPHICS-VIEW turns on or off the visualization of the graphics. It can be turned off to speed up the simulation by reducing the tasks not related to the simulation itself.

## THINGS TO NOTICE

Observe the graphics of Crimes per hour and try to understand the temporal patterns of the crimes during the simulation.

## THINGS TO TRY

Use the sliders for speed factors to change how fast agents change their awareness, or how fast the attractiveness of the places change. Also try to increase the number of offenders and see how crimes escalate.

## EXTENDING THE MODEL

Some speed factors are not implemented yet. That is the case for crime-hist-sf, attractiveness-sf and victim-history-sf. How it would be possible to include these factors to smothen the changes in the variables related to each speed factor?

## NETLOGO FEATURES

GIS library was used to load the map.

## RELATED MODELS

This model is not related to any other specific model, though it uses simular mechanisms as for random walk in networks based on a shapefile, like in the models shown by Andrew Crooks et al in [their book](https://uk.sagepub.com/en-gb/eur/agent-based-modelling-and-geographical-information-systems/book250134) **Agent-Based Modelling and Geographical Information Systems: A Practical Primer**.

## CREDITS AND REFERENCES

This model is related to the book *Agent-Based Modelling for Criminological Theory Testing and Development* (edited by Charlotte Gerritsen and Henk Elffers), more specifically to the Chapter 6, **"Creating a temporal pattern for street robberies using ABM and data from a small city in South East Brazil"**, by [Eric Araújo](http://bilbo.cc/) and Charlotte Gerritsen. Please refer to this book chapter when citing or using the code for future studies.