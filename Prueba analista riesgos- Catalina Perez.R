#===================================================================================#
#                                                                                   #
#        PRUEBA ANALISTA DE RIESGOS - ESTADOS FINANCIEROS – SUPERFINANCIERA         #
#                                   SKANDIA                                         #
#                                                                                   #
#                        POR: CATALINA PEREZ BALLESTEROS                            #
#                                                                                   #
#===================================================================================#

#----------------------------------------------------------
# 0. Limpiar entorno y cargar librerías 
#----------------------------------------------------------
rm(list = ls())
if(!is.null(dev.list())) dev.off()

library(readxl)
library(dplyr)
library(tidyr)
library(stringr)
library(openxlsx)
library(ggplot2)
library(scales)

#------------------------------------------------------------------------
# 1. Seleccionar los archivos desde la ruta y se crea una lista con ellos
#------------------------------------------------------------------------
ruta = "/Users/catalinaperez/Desktop/Indicadores Financieros"

archivos = list.files(
  path = ruta,
  pattern = "^ig_\\d{4}_\\d{2}\\.xls$", 
  full.names = TRUE
)

if (length(archivos) == 0) {
  stop("No se encontraron archivos ig_YYYY_MM.xls en la carpeta.")
}

#----------------------------------------------------------------------------------
# 2. Función ETL para cada archivo (Lee, extrae y transforma la jerarquía contable)
#----------------------------------------------------------------------------------
procesar_archivo = function(path_archivo) {
  
  archivo_nombre = basename(path_archivo)
  periodo = str_extract(archivo_nombre, "\\d{4}_\\d{2}") # Extrae fecha a aprtir del nombre del archivo
  if (is.na(periodo)) stop(paste("Archivo inválido:", archivo_nombre))
  
  anio = substr(periodo, 1, 4)
  mes  = substr(periodo, 6, 7)
  Fecha_estado = as.Date(paste0(anio, "-", mes, "-01"))
  
  df_raw = read_excel(path = path_archivo, col_names = FALSE)
  n_cols = ncol(df_raw)
  
  titulos_valores = df_raw %>%
    slice(11) %>%
    dplyr::select(4:all_of(n_cols)) %>% 
    unlist(use.names = FALSE) %>%
    as.character()
  
  titulos_valores[is.na(titulos_valores)] = paste0("valor_", which(is.na(titulos_valores)))
  
  #Identifica el inicio del BALANCE para leer la información correcta
  fila_inicio = which(str_detect(as.character(df_raw[[1]]), regex("^BALANCE", ignore_case = TRUE)))[1]
  if (is.na(fila_inicio)) return(NULL)
  
  #Nos quedamos con el estado financiero completo
  df = df_raw %>% slice((fila_inicio + 1):n())
  
  #Se nombran las primeras columnas 
  colnames(df)[1:3] = c("col_rubro", "col_subrubro", "col_detalle")
  colnames(df)[4:n_cols] = titulos_valores
  
#----------------------------------------------------------------------------------  
# 3. Se construye la lógica de las variables llamadas:  Rubro / Subrubro / Detalle
#---------------------------------------------------------------------------------- 
  
  df_procesado = df %>%
    mutate(
      Rubro = if_else(!is.na(col_rubro) & is.na(col_subrubro) & is.na(col_detalle),
                      str_to_upper(str_trim(as.character(col_rubro))), NA_character_),
      Subrubro = if_else(is.na(col_rubro) & !is.na(col_subrubro) & is.na(col_detalle),
                         str_to_upper(str_trim(as.character(col_subrubro))), NA_character_),
      Detalle = if_else(is.na(col_rubro) & !is.na(col_detalle),
                        str_to_upper(str_trim(as.character(col_detalle))), NA_character_)
    ) %>%
    fill(Rubro, .direction = "down") %>%
    fill(Subrubro, .direction = "down")

#---------------------------------------
# 4.  Dataframe final de cada balance
#---------------------------------------  
  
  df_final = df_procesado %>%
    mutate(INDEX = row_number(), Fecha = Fecha_estado) %>%
    dplyr::select(INDEX, Fecha, Rubro, Subrubro, Detalle, all_of(titulos_valores))
  
  return(df_final)
}

#----------------------------------------------------------
# 5. Se muestra la información final de la base completa
#----------------------------------------------------------
base_panel = bind_rows(lapply(archivos, procesar_archivo))
if (nrow(base_panel) == 0) stop("La base_panel está vacía.")

base_panel

#----------------------------------------------------------
# 6. Se exporta la base final a Excel para observarla mejor
#----------------------------------------------------------
archivo_salida = "estado_financiero_panel_completo.xlsx"

write.xlsx(
  x = base_panel,
  file = file.path(ruta, archivo_salida),
  overwrite = TRUE
)

#---------------------------------------------------------------------------------------------
# 7. Ahora elegiremos el emisor BANCO W S.A. para el estudio, y con él, bancos del mismo sector
#--------------------------------------------------------------------------------------------

#Se limpia la información quitando algunos NA y seleccionando las columnas adecuadas

emisores_interes = c("BANCO W S.A.", "BANCAMIA", "BANCO MUNDO MUJER S.A.")
emisores_existentes = intersect(emisores_interes, colnames(base_panel))

base_emisores_limpia = base_panel %>%
  dplyr::select(INDEX, Fecha, Rubro, Subrubro, Detalle, all_of(emisores_existentes)) %>%
  filter(if_any(all_of(emisores_existentes), ~ !is.na(.)))

#A partir de esta base realizaremos un analisis gráfico de los tipos de riesgo 

#======================================================================
# 8. ÍNDICE DE MOROSIDAD BANCO W y CARTERA C, D Y E /  CARTERA BRUTA
#======================================================================

banco <- "BANCO W S.A."

morosidad_bw <- base_emisores_limpia %>%
  filter(
    Rubro == "INDICADORES DE CARTERA Y LEASING",
    Subrubro == "CARTERA C, D Y E /  CARTERA BRUTA"
  ) %>%
  dplyr::select(Fecha, Valor = !!sym(banco)) %>%
  mutate(
    Valor = as.numeric(str_replace(Valor, ",", "."))  # 🔴 coma → punto
  ) %>%
  arrange(Fecha)

tema_banca <- theme_minimal(base_size = 13) +
  theme(
    panel.grid.minor = element_blank(),
    panel.grid.major.x = element_blank(),
    plot.title = element_text(face = "bold", size = 14),
    axis.title = element_text(face = "bold"),
    axis.text = element_text(color = "black")
  )

graf_morosidad <- ggplot(morosidad_bw, aes(x = Fecha, y = Valor)) +
  geom_line(color = "#003A8F", linewidth = 1.3) +
  geom_point(color = "#003A8F", size = 3) +
  scale_y_continuous(labels = scales::percent_format(accuracy = 0.1)) +
  scale_x_date(
    breaks = morosidad_bw$Fecha,
    date_labels = "%Y"
  ) +
  labs(
    title = "Índice de Morosidad (C, D y E)",
    subtitle = "Banco W S.A.",
    x = "Fecha de corte",
    y = "Porcentaje de cartera"
  ) +
  tema_banca

print(graf_morosidad)

#COBERTURA DE CARTERA RIESGOSA

cobertura_bw <- base_emisores_limpia %>%
  filter(
    Rubro == "INDICADORES DE CARTERA Y LEASING",
    Subrubro == "COBERTURA C, D Y E"
  ) %>%
  dplyr::select(Fecha, Valor = !!sym(banco)) %>%
  mutate(Valor = as.numeric(str_replace(Valor, ",", "."))) %>%
  arrange(Fecha)

graf_cobertura <- ggplot(cobertura_bw, aes(x = Fecha, y = Valor)) +
  geom_line(color = "#5B9BD5", linewidth = 1.3) +
  geom_point(color = "#5B9BD5", size = 3) +
  scale_y_continuous(labels = scales::percent_format(accuracy = 0.1)) +
  scale_x_date(breaks = cobertura_bw$Fecha, date_labels = "%Y") +
  labs(
    title = "Cobertura de cartera C, D y E",
    subtitle = "Banco W S.A.",
    x = "Fecha de corte",
    y = "Cobertura (%)"
  ) +
  tema_banca

print(graf_cobertura)


#----------------------------------------------------------
# 8.1 INDICADOR DE RENTABILIDAD PATRIMONIAL (ROE)
#----------------------------------------------------------
roe_bw <- base_emisores_limpia %>%
  filter(
    Rubro == "APALANCAMIENTO Y RENTABILIDAD",
    Subrubro == "UTILIDAD/PATRIMONIO"
  ) %>%
  dplyr::select(Fecha, Valor = !!sym(banco)) %>%
  mutate(Valor = as.numeric(str_replace(Valor, ",", "."))) %>%
  arrange(Fecha)

graf_roe <- ggplot(roe_bw, aes(x = Fecha, y = Valor)) +
  geom_line(color = "#2F5597", linewidth = 1.3) +
  geom_point(color = "#2F5597", size = 3) +
  scale_y_continuous(labels = scales::percent_format(accuracy = 0.1)) +
  scale_x_date(breaks = roe_bw$Fecha, date_labels = "%Y") +
  labs(
    title = "Indicador de Rentabilidad Patrimonial",
    subtitle = "Banco W S.A.",
    x = "Fecha de corte",
    y = "Rentabilidad (%)"
  ) +
  tema_banca

print(graf_roe)


#=======================================================================================
# 8.2. INDICADOR DE SOLVENCIA – ACTIVOS / PATRIMONIO
#=======================================================================================

banco <- "BANCO W S.A."

solvencia_bw <- base_emisores_limpia %>%
  filter(
    Rubro == "APALANCAMIENTO Y RENTABILIDAD",
    Subrubro == "ACTIVOS/PATRIMONIO"
  ) %>%
  dplyr::select(Fecha, Valor = !!sym(banco)) %>%
  mutate(Valor = as.numeric(str_replace(Valor, ",", "."))) %>%
  arrange(Fecha)

tema_banca <- theme_minimal(base_size = 13) +
  theme(
    panel.grid.minor = element_blank(),
    panel.grid.major.x = element_blank(),
    plot.title = element_text(face = "bold", size = 14),
    axis.title = element_text(face = "bold"),
    axis.text = element_text(color = "black")
  )

graf_solvencia <- ggplot(solvencia_bw, aes(x = Fecha, y = Valor)) +
  geom_line(color = "#7F6000", linewidth = 1.3) +
  geom_point(color = "#7F6000", size = 3) +
  scale_x_date(breaks = solvencia_bw$Fecha, date_labels = "%Y") +
  labs(
    title = "Indicador de Solvencia",
    subtitle = "Activos / Patrimonio – Banco W S.A.",
    x = "Fecha de corte",
    y = "Veces"
  ) +
  tema_banca

print(graf_solvencia)

