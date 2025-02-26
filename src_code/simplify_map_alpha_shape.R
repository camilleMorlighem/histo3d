library(rgdal)
library(alphahull)
library(igraph)
library(shapefiles)
library(raster)
library(rgeos)
library(wkb)
library(sf)
library(GISTools)


###### This script generalises a set of polygons based on alpha-shape generalisation. 
###### Credit: Arteaga, Mauricio. (2013). Historical map polygon and feature extractor. 
#MapInteract 2013 - Proceedings of the 1st ACM SIGSPATIAL International Workshop on 
#MapInteraction. 10.1145/2534931.2534932. 
#Their source code: https://github.com/nypl-spacetime/map-vectorizer


args <- commandArgs(trailingOnly = TRUE)
filepath = args[2]
layer = args[3]
finalout = args[4]

myPolygons  = readOGR(filepath,layer=layer)

alpha= as.numeric(args[1])#2 # 1.6 is another option, dependant on polygon areas that are being extracted (see minarea/maxarea below)
numsample=1000

num = length(myPolygons)
poly.list = vector('list')

sps=SpatialPolygons(list(), , myPolygons@proj4string)
output = SpatialPolygonsDataFrame(sps, data.frame())

for (i in 1: num) {
	poly = myPolygons@polygons[[i]]

	if (TRUE) { #(poly@area > minarea && poly@area < maxarea) {
		types = c("hexagonal","regular","nonaligned","stratified")
		attempts = 1
		x.as = 0
		error = 1
		# try to find a functional ashape with any of the sampling types above
		while (attempts <= length(types) && error > 0) {
			pts = spsample(poly, n=numsample, type=types[attempts])
			x.coords = coordinates(pts)
			x.as = tryCatch(
				{
					ashape(x.coords,alpha=alpha)
				}
				,warning = function (w) {}
				,error = function (e) {}
			)
			# cat("Attempts: ", attempts, " class: ", class(x.as), "\n")
			if ( class(x.as)=="ashape" ) {
				x.asg = graph.edgelist(cbind(as.character(x.as$edges[, "ind1"]), as.character(x.as$edges[, "ind2"])), directed = FALSE)
				error = 0
				# try to fix circularity
				if (error == 0 && any(degree(x.asg) != 2)) {
					x.asg <- delete.vertices(x.asg, which(degree(x.asg) == 1))
				}
				# try to fix multiple circles (when shape has big holes inside)
				if (error == 0 && clusters(x.asg)$no > 1) {
					# get the components
					components = decompose.graph(x.asg, min.vertices = 3, max.comps = 1)
					# we are assuming the FIRST cluster is the LARGEST (external container)
					x.asg = components[[1]]
					# cat(poly@ID, ": Graph composed of more than one circle", "\n")
				}
				if (error == 0 && any(degree(x.asg) != 2)) {
					# cat(poly@ID, ": Graph not circular", "\n")
					error = 2
				}
				if (!is.connected(x.asg)) {
					# cat(poly@ID, ": Graph not connected", "\n")
					error = 1
				}
				if (error == 0) {
					cutg = x.asg - E(x.asg)[1]
					# find chain end points
					ends = names(which(degree(cutg) == 1))
					path = get.shortest.paths(cutg, ends[1], ends[2])[[1]]
					# this is an index into the points
					pathX = as.numeric(V(x.asg)[path[[1]]]$name)
					# join the ends
					pathX = c(pathX, pathX[1])
					p = Polygon(x.as$x[pathX, ])
					# now we simplify the polygon (reduce edge count)
					temp <- as.data.frame(p@coords)
					names(temp) <- c("x","y")
					#simple = dp(temp,0.5)
					#p@coords <- as.matrix(cbind(simple$x, simple$y))
					# finished simplifying
					ps = Polygons(list(p),1)
					sps = SpatialPolygons(list(ps), , myPolygons@proj4string)
					data = data.frame(FeaID=myPolygons[i,]$FeaID)#, area_raw= myPolygons[i,]$area_raw, n_vert_raw=myPolygons[i,]$n_vert_raw) # the polygon ID
					SpatialPolygonsDataFrame(sps, data)
					#output = SpatialPolygonsDataFrame(sps, data)
					output=rbind(output, SpatialPolygonsDataFrame(sps, data))
				
					}
			}
			attempts = attempts + 1
		}
		if (error > 0) {
			#writeLines(paste((i)," could not be written: ", error, sep=""), logfile)
		  paste((i)," could not be written: ")
		}
	}
}

writeOGR(output, paste(finalout, as.integer(alpha), ".shp", sep=""), layer, driver="ESRI Shapefile", overwrite_layer = TRUE)


