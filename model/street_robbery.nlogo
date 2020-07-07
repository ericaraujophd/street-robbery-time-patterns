extensions [ gis ]

;; --------------------------------
;;      GLOBALS
;; -------------------------------

globals [
  ; map globals
  buildings-dataset
  roads-dataset
  destination-patch       ;; auxiliar to find the vertex closest to the patch
  min-ticks-wait          ;; min time of wait after a person gets to their destination
  max-ticks-wait          ;; max time of wait after a person gets to their destination
  popular-times           ;; percentage of people active over time slots of 1h
  offenders-popular-times ;; percentage of offenders active over time slots of 1h
  crime-rates-per-hour    ;; vector with the percentage of crimes ocurred by 1h slot
  cur-day                 ;; day
  cur-hour                ;; hour
  cur-min                 ;; min
  week-day                ;; day of the week
  prob-standby            ;; probability of an agent to go standby
  total-crimes            ;; count of the crimes

  #-vertices
  report-crimes-per-hour  ;; vector to report the crimes per hour
]

;; --------------------------------
;;      NEW BREEDS
;; -------------------------------
breed [ vertices vertex ]
vertices-own [
  myneighbors ;; agentset of neighbouring vertices
  test

  ;; variables used in path-selection function
  dist        ;; distance from the original point to here
  done        ;; 1 if has calculated the shortest path through this point, 0 otherwise
  lastnode    ;; last node to this point in shortest path

]

breed [ people person ]
people-own [
  destination       ;; next vertex to go
  mynode            ;; current node
  active?           ;; after node reaches destination, it stays there for a while
  home-vertex       ;; home vertex
  ;; OFFENDERS VARIABLES
  offender?         ;; if the node is an offender
  crimes-committed  ;; number of crimes committed
  victim            ;; potential victim selected
  motivation
  ;; CITIZENS VARIABLES
  awareness         ;; awareness level of the agent
  victim-history    ;; if the person was a victim recently, this variable is gonna be higher
  robbed?           ;; if the person was robbed
  gender            ;; 0 male 1 female
  age               ;; age of the agent
]

patches-own [
  corner?        ;; if path is one of the corner streets
  closest-vertex ;; the closest vertex of the corner patches (only for corner patches)
  ;; MODEL VARIABLES
  num-people-here   ;; number of people (no offenders) in a patch
  density           ;; amount of people in the node
  crime-hist-vertex ;; if there was a crime in this vertex recently
  attractiveness    ;; overall attractiveness of the location
  time-effect       ;; time of the day effect
  crimes-in-vertex  ;; total crimes in the vertex


]

;; --------------------------------
;;      SETUP PROCEDURES
;; -------------------------------
to setup
  ca
  setup-map
  setup-vertices
  setup-globals
  setup-citizens

  reset-ticks
end


;; GLOBALS
to setup-globals

  set cur-day 0          ;; starts on day 0
  set cur-hour 0
  set cur-min 0
  set report-crimes-per-hour [0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 ]

  set #-vertices count vertices
end

;; MAP READING
to setup-map
  ; size of the patch map
  resize-world -180 180 -115 115
  set-patch-size 1.5
  ask patches [ set pcolor white ]

  ; Load all of our datasets
  set buildings-dataset gis:load-dataset "./data/buildings2.shp"
  set roads-dataset gis:load-dataset "./data/roads.shp"
  ; Set the world envelope to the union of all of our dataset's envelopes
  gis:set-world-envelope (gis:envelope-union-of (gis:envelope-of buildings-dataset)
                                                (gis:envelope-of roads-dataset))

  ; display buildings
  if show-buildings = True [
    ; display roads
    gis:set-drawing-color gray
    gis:draw roads-dataset 1

    gis:set-drawing-color blue
    gis:draw buildings-dataset 1
  ]
end


;; ROAD NETWORK CREATION
; following example 8.4.2
to setup-vertices
  foreach gis:feature-list-of roads-dataset [
    road-feature ->
    ;; for the road feature, iterate over the vertices that make it up
    foreach gis:vertex-lists-of road-feature [
      v ->
      let previous-node-pt nobody ;; previous node is used to link nodes together
      ;; for each vertex, iterate over its individual points
      foreach v [
        node ->
        ;; find the location of the node and create a new vertex agent there
        let location gis:location-of node
        if not empty? location [
          create-vertices 1 [
            set myneighbors n-of 0 turtles ;; empty
            set xcor item 0 location
            set ycor item 1 location
            ask patch item 0 location item 1 location [ ;; defining the street corners
              set corner? true
            ]
            set size 2
            set shape "circle"
            set color red
            set hidden? true

            ;; create a link to the previous node
            ifelse previous-node-pt = nobody [
              ;; first vertex in feature, so do nothing
            ][
              create-link-with previous-node-pt ;; create link to previous node
            ]
            ;; remember THIS node so that the next one can link back to it
            set previous-node-pt self
          ]
        ]
      ]
    ]
  ]

  ;; delete duplicate vertices (there may be more than one vertice on the same patch due
  ;; to reducing size of the map). Therefore, this map is simplified from the original map.
  delete-duplicates
  ask vertices [set myneighbors link-neighbors]
  delete-not-connected
  ask vertices [set myneighbors link-neighbors]

  ask patches with [ corner? = true ][
    set closest-vertex min-one-of vertices in-radius 50 [distance myself]
    ;; initiate the variables for attractiveness
    set attractiveness 0
    set crime-hist-vertex 0
  ]

  ask links [set thickness 1.4 set color black]
end

to setup-citizens
  create-people num-people [
    set shape "person"
    set size 5
    set color green

    set destination nobody                          ; person hasn't destination yet
    ;set last-stop nobody
    set active? true
    set mynode one-of vertices move-to mynode       ; move person to one of the vertices
    set home-vertex mynode                          ; define the vertice as home

    ; for citizens
    set robbed? false                               ; if citizen was recently robbed
    set victim-history 0                            ; memory history of the agent (victim)
    set awareness random-float 1                    ; each person has a random awareness at the beginning
  ]

  ask n-of num-offenders people [                   ; create offenders
    set offender? true
    set color red
    set size 8
    set crimes-committed 0
    set motivation random-float 1
  ]
end

;; --------------------------------
;;      GO PROCEDURES
;; -------------------------------

to go
  time-update
  random-walk
  update-attractiveness
  update-citizens
  commit-crime

  draw-plots

end


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; UPDATE THE ATTRACTIVENESS OF THE VERTICES IN THE MAP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
to update-attractiveness
  ask patches with [corner? = true] [
    ;; the higher the density (max 1) the better for the offender
    set num-people-here count people-here with [active? = true and offender? != true]
    ifelse num-people-here > 0 [
      set density 1 / (num-people-here ^ 2)
    ][ set density 0 ]

    ;; the higher the crime history, the better for the offender
    set crime-hist-vertex crime-hist-vertex * crime-hist-sf

    ;; for the offender -> the higher the better
    set attractiveness (1 - lighting ) * density

  ]

end


;; LIGHTING IN THE CITY ACCORDING TO THE TIME OF THE DAY (in ticks)
to-report lighting
  ;; half light at 6am and 6pm. Pick sun at 12pm, and darkness at 12am.
  ;; report 0.5 + 0.5 * sin ( pi * (x - 36 ) / 72 )
  ifelse cur-hour > 18 or cur-hour < 7 [
    ; 0.4 before
    report 0.3
  ][ report 0.9]
  ;; report 0.5 + 0.5 * sin ( 2.5 * (ticks - 36) )
end




;; SINOIDAL MODEL FOR THE EFFECT OF THE TIME
to-report time-crime-effect [ t ]
  ;; in radians
  ;; report 0.5 - 0.5 * sin ( pi * (t - 2) / 12)
  ;; in degrees ( radians * 180 / pi )
  report 0.5 - 0.5 * sin ( 15 * (t - 2))
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; UPDATE THE AWARENESS AND CRIME HISTORY OF THE CITIZENS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
to update-citizens
  ask people [
    ;    ifelse robbed? [
    ;      set victim-history 1
    ;      set robbed? false
    ;      set color blue
    ;    ][ set victim-history victim-history * victim-history-sf ]

    ;; awareness-balance gives different weights for victim-history and attractiveness of the place
    ;set awareness (awareness-balance * victim-history + (1 - awareness-balance) * (1 - [ attractiveness ] of mynode) )
    set awareness awareness + awareness-sf * ( attractiveness - awareness )
  ]

end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; ASK OFFENDERS TO MAKE DECISIONS ABOUT COMMITTING THE CRIME
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
to commit-crime
  ; ask offenders to evaluate the possibility of commiting a crime
  ask people with [offender? = true and active? = true] [
    if motivation > motivation-threshold [
      if [density] of mynode > 0 [
        set victim min-one-of people-here with [active? = true and offender? != true] [awareness]
        if victim != nobody [
          let rfloat random-float 1
          if rfloat < (((1 - [awareness] of victim) + motivation ) / 2 ) [
            set crimes-committed crimes-committed + 1
            set total-crimes total-crimes + 1
            set crimes-in-vertex crimes-in-vertex + 1
            set crime-hist-vertex 1
            set report-crimes-per-hour replace-item cur-hour report-crimes-per-hour ((item cur-hour report-crimes-per-hour ) + 1)
            ; ask victim [ set robbed? true ]

            ;type "hour: " type cur-hour type victim type " with awareness " type [awareness] of victim type " was robbed by " type self type " with a motivation of " type motivation type "\n"
            ;type rfloat type "\t" type ((1 - [awareness] of victim) * motivation ) type "\n"
            set motivation random-float 0.25


          ]
        ]
      ]
    ]
    ;; motivation adjustment every day
    ;if cur-hour = 0 [
    set motivation motivation + 0.05 * (random-float motivation-sf)
    if motivation > 1 [ set motivation 1 ]
    ;]

  ]
end



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; WALKING ALGORITHM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to random-walk
  ask people [
    ; if it is full hour, change the standby nodes
    set prob-standby people-on-the-streets ;; item cur-hour popular-times

    ifelse offender? != true [
      ifelse random-float 1 > prob-standby [
        set active? false
        set hidden? true
      ][
        set active? true
        set hidden? false
      ]
    ][
      ifelse random-float 1 > robbers-on-the-streets [
        set active? false
        set hidden? true
      ][
        set active? true
        set hidden? false
      ]
    ]

    if active? = true [
      set mynode one-of [myneighbors] of mynode
      move-to mynode
    ]
  ]
  tick
end


to-report people-on-the-streets
  ;; in radians
  ;; report 0.5 + 0.5 * sin ( pi * (t - 54) / 72)
  ;; in degrees ( radians * 180 / pi )
  report 0.51 + 0.5 * sin ( 2.5 * (ticks - 54))
end

to-report robbers-on-the-streets
  ;report 0.5 - 0.5 * sin (2.5 * (ticks - 24 ))
  report 0.5 - 0.5 * sin (2.5 * (ticks - 12 ))
end

;;;;;;;;;;;;;;;;; auxiliar functions;;;;;;;;;;;;;;;;;;;;;;;;;;

to delete-duplicates
  ask vertices [
    if count vertices-here > 1[
      ask other vertices-here [
        ask myself [
          create-links-with other [link-neighbors] of myself
        ]
        die
      ]
    ]
  ]

end

to delete-not-connected
  ask vertices [set test 0]
  ask one-of vertices [set test 1]
  repeat 500 [
    ask vertices with [test = 1] [
      ask myneighbors [
        set test 1
      ]
    ]
  ]
  ask vertices with [test = 0][die]
end

to time-update
  set cur-min (cur-min + 10)

  if cur-min = 60 [
    set cur-hour (cur-hour + 1)
    set cur-min 0
  ]

  if cur-hour = 24 [
    set cur-day (cur-day + 1)
    set cur-hour 0
  ]

  set week-day (cur-day mod 7)

end

; calculate density average in the vertices
to-report density-average
  report count people with [active? = true]  / count vertices
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;; PLOTS ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; function that draws the plots
to draw-plots
  if ticks mod 288 = 0 [
    clear-all-plots                                    ; clear plots in order to make simulation faster
    ;no-display
  ]
  if graphics-view [
    ;; Crimes per hour graphics
    set-current-plot "Crimes per hour"
    create-temporary-plot-pen "report_crimes"
    set-plot-pen-mode 1
    foreach (range 0 24)[
      x -> plotxy x item x report-crimes-per-hour
    ]

    ;; Environmental variables
    set-current-plot "Environmental Variables"
    create-temporary-plot-pen "Lighting"
    set-plot-pen-color 15
    plot lighting

    ; plot for attractiveness
    create-temporary-plot-pen "Attractiveness"
    set-plot-pen-color 105
    plot mean [attractiveness] of patches with [corner? = true]

    ; plot for density
    set-current-plot "Density"
    create-temporary-plot-pen "Density"
    set-plot-pen-color 105
    plot density-average
  ]
end


; Advanced logistic function for the model calculations
to-report alogistic [ x ]
  let omega 5
  let tau 20
  report ((1 / (1 + e ^ (- omega * (x - tau) ) ) ) - (1 / (1 + e ^ (tau * omega)))) * (1 + e ^ (- omega * tau) )
end
@#$#@#$#@
GRAPHICS-WINDOW
214
59
763
414
-1
-1
1.5
1
10
1
1
1
0
1
1
1
-180
180
-115
115
1
1
1
ticks
30.0

BUTTON
1
10
67
43
setup
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SWITCH
183
16
337
49
show-buildings
show-buildings
1
1
-1000

SLIDER
3
90
175
123
num-people
num-people
50
15000
10000.0
50
1
NIL
HORIZONTAL

PLOT
811
356
1329
476
Density
Time
Variable
0.0
10.0
0.0
1.0
true
true
"" ""
PENS

MONITOR
589
10
646
55
day
cur-day
17
1
11

MONITOR
652
11
709
56
hour
cur-hour
17
1
11

MONITOR
717
11
774
56
min
cur-min
17
1
11

BUTTON
2
49
57
82
NIL
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
0

BUTTON
63
49
118
82
NIL
go
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
0

SLIDER
3
135
175
168
num-offenders
num-offenders
0
100
10.0
1
1
NIL
HORIZONTAL

MONITOR
507
10
578
55
Week Day
week-day
0
1
11

SLIDER
4
390
176
423
crime-hist-sf
crime-hist-sf
0
1
0.0
0.1
1
NIL
HORIZONTAL

SLIDER
4
428
176
461
attractiveness-sf
attractiveness-sf
0
1
0.0
0.1
1
NIL
HORIZONTAL

SLIDER
5
467
177
500
victim-history-sf
victim-history-sf
0
1
0.0
0.1
1
NIL
HORIZONTAL

TEXTBOX
19
195
169
220
Speed Factors
20
14.0
1

PLOT
810
11
1042
207
Crimes per hour
time (h)
# of crimes
0.0
24.0
0.0
100.0
false
false
"" ""
PENS

MONITOR
1054
13
1143
58
NIL
total-crimes
17
1
11

PLOT
810
223
1329
348
Environmental Variables
time
Variables
0.0
10.0
0.0
1.0
true
true
"" ""
PENS

SLIDER
5
231
180
264
awareness-sf
awareness-sf
0
1
0.8
0.05
1
NIL
HORIZONTAL

SLIDER
5
272
180
305
crime-hist-balance
crime-hist-balance
0
1
0.0
0.05
1
NIL
HORIZONTAL

SLIDER
339
425
511
458
motivation-sf
motivation-sf
0
0.1
0.01
0.0001
1
NIL
HORIZONTAL

MONITOR
1055
71
1191
116
People on the streets
count people with [active? = true]
17
1
11

SLIDER
5
312
181
345
motivation-threshold
motivation-threshold
0
1
0.9
0.1
1
NIL
HORIZONTAL

SWITCH
346
15
490
48
graphics-view
graphics-view
0
1
-1000

TEXTBOX
12
363
162
382
Future additions
15
15.0
1

@#$#@#$#@
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
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.1.1
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
<experiments>
  <experiment name="phase_01" repetitions="1" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <exitCondition>cur-day = 50</exitCondition>
    <metric>(list (report-crimes-per-hour) (total-crimes))</metric>
    <steppedValueSet variable="awareness-sf" first="0.5" step="0.1" last="1"/>
    <steppedValueSet variable="motivation-sf" first="0.01" step="0.01" last="0.05"/>
    <steppedValueSet variable="motivation-threshold" first="0.1" step="0.1" last="0.9"/>
    <enumeratedValueSet variable="num-offenders">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="victim-history-sf">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="attractiveness-sf">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-people">
      <value value="10000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="graphics-view">
      <value value="false"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="phase_02" repetitions="50" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <exitCondition>cur-day = 50</exitCondition>
    <metric>(list (report-crimes-per-hour) (total-crimes))</metric>
    <enumeratedValueSet variable="awareness-sf">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="motivation-sf">
      <value value="0.04"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="motivation-threshold">
      <value value="0.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-offenders">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-people">
      <value value="10000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="graphics-view">
      <value value="false"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="phase_03" repetitions="10" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <exitCondition>cur-day = 366</exitCondition>
    <metric>(list (report-crimes-per-hour) (total-crimes))</metric>
    <enumeratedValueSet variable="awareness-sf">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="motivation-sf">
      <value value="0.04"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="motivation-threshold">
      <value value="0.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-offenders">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-people">
      <value value="10000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="graphics-view">
      <value value="false"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="phase_04a" repetitions="100" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <exitCondition>cur-day = 366</exitCondition>
    <metric>(list (report-crimes-per-hour) (total-crimes))</metric>
    <enumeratedValueSet variable="awareness-sf">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="motivation-sf">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="motivation-threshold">
      <value value="0.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-offenders">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-people">
      <value value="10000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="graphics-view">
      <value value="false"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="phase_04b" repetitions="10" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <exitCondition>cur-day = 366</exitCondition>
    <metric>(list (report-crimes-per-hour) (total-crimes))</metric>
    <enumeratedValueSet variable="awareness-sf">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="motivation-sf">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="motivation-threshold">
      <value value="0.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-offenders">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-people">
      <value value="10000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="graphics-view">
      <value value="false"/>
    </enumeratedValueSet>
  </experiment>
</experiments>
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
