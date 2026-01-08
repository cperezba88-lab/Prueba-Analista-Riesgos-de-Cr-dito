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

emisores_interes

tema_banca <- theme_minimal(base_size = 13) +
  theme(
    panel.grid.minor = element_blank(),
    panel.grid.major.x = element_blank(),
    plot.title = element_text(face = "bold", size = 14),
    plot.subtitle = element_text(size = 11),
    axis.title = element_text(face = "bold"),
    axis.text = element_text(color = "black"),
    legend.position = "top"
  )


#==============================================================
# 9. ANÁLISIS COMPARATIVO: BANCO W vs PARES vs SECTOR
#============================================================

#---------------------------
# Función base comparativa (USA base_panel)
#---------------------------
construir_base_comparativa <- function(rubro, subrubro) {
  
  banco_w <- "BANCO W S.A."
  pares   <- c("BANCAMIA", "BANCO MUNDO MUJER S.A.")
  
  sector_posibles <- c("Bancos Privados Nacionales", "Bancos Privados")
  sector <- intersect(sector_posibles, colnames(base_panel))
  
  if (length(sector) == 0) {
    stop("No se encontró columna de Bancos Privados en base_panel.")
  }
  sector <- sector[1]
  
  base_panel %>%
    filter(
      Rubro == rubro,
      Subrubro == subrubro
    ) %>%
    select(
      Fecha,
      all_of(c(banco_w, pares, sector))
    ) %>%
    mutate(
      Banco_W = as.numeric(str_replace(.data[[banco_w]], ",", ".")),
      Pares = rowMeans(
        cbind(
          as.numeric(str_replace(.data[[pares[1]]], ",", ".")),
          as.numeric(str_replace(.data[[pares[2]]], ",", "."))
        ),
        na.rm = TRUE
      ),
      Sector = as.numeric(str_replace(.data[[sector]], ",", "."))
    ) %>%
    select(Fecha, Banco_W, Pares, Sector) %>%
    pivot_longer(
      cols = -Fecha,
      names_to = "Grupo",
      values_to = "Valor"
    ) %>%
    arrange(Fecha)
}


# 9.1 MOROSIDAD COMPARATIVA
#==========================================================

morosidad_comp <- construir_base_comparativa(
  "INDICADORES DE CARTERA Y LEASING",
  "CARTERA C, D Y E /  CARTERA BRUTA"
) %>%
  filter(!is.na(Valor))   

ggplot(
  morosidad_comp,
  aes(x = Fecha, y = Valor, color = Grupo, group = Grupo)
) +
  geom_line(
    aes(linewidth = Grupo),
    na.rm = TRUE
  ) +
  scale_linewidth_manual(
    values = c(
      Banco_W = 1.6,
      Pares   = 1.2,
      Sector  = 1.1
    ),
    guide = "none"
  ) +
  scale_color_manual(
    values = c(
      Banco_W = "#C00000",   # Banco W
      Pares   = "#1F4E79",   # Pares
      Sector  = "#7F7F7F"    # Sector
    ),
    labels = c(
      Banco_W = "Banco W S.A.",
      Pares   = "Pares (Promedio)",
      Sector  = "Bancos Privados Nacionales"
    )
  ) +
  scale_y_continuous(
    labels = scales::percent_format(accuracy = 0.1)
  ) +
  scale_x_date(
    breaks = sort(unique(morosidad_comp$Fecha)),
    labels = function(x) format(x, "%b-%Y")
  ) +
  labs(
    title = "Índice de Morosidad (CARTERA C, D Y E /  CARTERA BRUTA)",
    subtitle = "Banco W vs Pares vs Bancos Privados Nacionales",
    x = "Fecha de corte",
    y = "Porcentaje de cartera",
    color = ""
  ) +
  tema_banca

#==========================================================
# 9.2 COBERTURA C, D Y E – COMPARATIVA
#==========================================================

cobertura_comp <- construir_base_comparativa(
  "INDICADORES DE CARTERA Y LEASING",
  "COBERTURA C, D Y E"
) %>%
  filter(!is.na(Valor))

ggplot(
  cobertura_comp,
  aes(x = Fecha, y = Valor, color = Grupo, group = Grupo)
) +
  geom_line(
    aes(linewidth = Grupo),
    na.rm = TRUE
  ) +
  scale_linewidth_manual(
    values = c(
      Banco_W = 1.6,
      Pares   = 1.2,
      Sector  = 1.1
    ),
    guide = "none"
  ) +
  scale_color_manual(
    values = c(
      Banco_W = "#C00000",   # Banco W
      Pares   = "#1F4E79",   # Pares
      Sector  = "#7F7F7F"    # Sector
    ),
    labels = c(
      Banco_W = "Banco W S.A.",
      Pares   = "Pares (Promedio)",
      Sector  = "Bancos Privados Nacionales"
    )
  ) +
  scale_y_continuous(
    labels = scales::percent_format(accuracy = 0.1)
  ) +
  scale_x_date(
    breaks = sort(unique(cobertura_comp$Fecha)),
    labels = function(x) format(x, "%b-%Y")
  ) +
  labs(
    title = "Cobertura de Cartera C, D y E",
    subtitle = "Banco W vs Pares vs Bancos Privados Nacionales",
    x = "Fecha de corte",
    y = "Cobertura (%)",
    color = ""
  ) +
  tema_banca
#==========================================================
# 9.3 RENTABILIDAD PATRIMONIAL (ROE) – COMPARATIVA
#==========================================================

roe_comp <- construir_base_comparativa(
  "APALANCAMIENTO Y RENTABILIDAD",
  "UTILIDAD/PATRIMONIO"
) %>%
  filter(!is.na(Valor))

ggplot(
  roe_comp,
  aes(x = Fecha, y = Valor, color = Grupo, group = Grupo)
) +
  geom_line(
    aes(linewidth = Grupo),
    na.rm = TRUE
  ) +
  scale_linewidth_manual(
    values = c(
      Banco_W = 1.6,
      Pares   = 1.2,
      Sector  = 1.1
    ),
    guide = "none"
  ) +
  scale_color_manual(
    values = c(
      Banco_W = "#C00000",
      Pares   = "#1F4E79",
      Sector  = "#7F7F7F"
    ),
    labels = c(
      Banco_W = "Banco W S.A.",
      Pares   = "Pares (Promedio)",
      Sector  = "Bancos Privados Nacionales"
    )
  ) +
  scale_y_continuous(
    labels = scales::percent_format(accuracy = 0.1)
  ) +
  scale_x_date(
    breaks = sort(unique(roe_comp$Fecha)),
    labels = function(x) format(x, "%b-%Y")
  ) +
  labs(
    title = "Rentabilidad Patrimonial (ROE)",
    subtitle = "Banco W vs Pares vs Bancos Privados Nacionales",
    x = "Fecha de corte",
    y = "Rentabilidad (%)",
    color = ""
  ) +
  tema_banca



#=======================================================================================
# 10. COMPOSICIÓN DE LA CARTERA (% POR MODALIDAD)
#     Banco W vs Pares vs Bancos Privados Nacionales
#=======================================================================================

#---------------------------
# Definición de grupos
#---------------------------
banco_w <- "BANCO W S.A."
pares_bancos <- c("BANCAMIA", "BANCO MUNDO MUJER S.A.")

sector_posibles <- c("Bancos Privados Nacionales", "Bancos Privados")
sector <- intersect(sector_posibles, colnames(base_panel))

if (length(sector) == 0) {
  stop("No se encontró columna de Bancos Privados Nacionales en base_panel.")
}
sector <- sector[1]

#---------------------------
# Último periodo disponible
#---------------------------
ultima_fecha <- max(base_panel$Fecha, na.rm = TRUE)

#---------------------------
# Construcción de base de composición
#---------------------------
composicion_base <- base_panel %>%
  filter(
    Fecha == ultima_fecha,
    Rubro == "CARTERA Y LEASING POR MODALIDAD (POR CALIFICACION)",
    Subrubro %in% c("% COMERCIAL", "% VIVIENDA", "% MICROCREDITO")
  ) %>%
  mutate(
    Modalidad = case_when(
      Subrubro == "% COMERCIAL"    ~ "Comercial",
      Subrubro == "% VIVIENDA"     ~ "Vivienda",
      Subrubro == "% MICROCREDITO" ~ "Microcrédito"
    ),
    Banco_W = as.numeric(str_replace(.data[[banco_w]], ",", ".")),
    Pares = rowMeans(
      cbind(
        as.numeric(str_replace(.data[[pares_bancos[1]]], ",", ".")),
        as.numeric(str_replace(.data[[pares_bancos[2]]], ",", "."))
      ),
      na.rm = TRUE
    ),
    Sector = as.numeric(str_replace(.data[[sector]], ",", "."))
  ) %>%
  select(Modalidad, Banco_W, Pares, Sector) %>%
  pivot_longer(
    cols = c(Banco_W, Pares, Sector),
    names_to = "Grupo",
    values_to = "Porcentaje"
  ) %>%
  mutate(
    Grupo = factor(
      Grupo,
      levels = c("Banco_W", "Pares", "Sector"),
      labels = c("Banco W S.A.", "Pares (Promedio)", "Bancos Privados Nacionales")
    )
  )

#---------------------------
# Gráfico de barras apiladas con etiquetas
#---------------------------
graf_composicion <- ggplot(
  composicion_base,
  aes(x = Grupo, y = Porcentaje, fill = Modalidad)
) +
  geom_col(width = 0.65) +
  geom_text(
    aes(label = percent(Porcentaje, accuracy = 1)),
    position = position_stack(vjust = 0.5),
    color = "black",
    size = 4,
    fontface = "bold"
  ) +
  scale_y_continuous(
    labels = percent_format(accuracy = 1),
    expand = expansion(mult = c(0, 0.05))
  ) +
  scale_fill_manual(
    values = c(
      "Comercial"    = "#C00000",
      "Vivienda"     = "#5B9BD5",
      "Microcrédito" = "#9BBB59"
    )
  ) +
  labs(
    title = "Composición de la Cartera por Modalidad",
    subtitle = paste(
      "Banco W vs Pares vs Bancos Privados Nacionales –",
      format(ultima_fecha, "%b-%Y")
    ),
    x = "",
    y = "Participación (%)",
    fill = ""
  ) +
  tema_banca

print(graf_composicion)


#=======================================================================================
# 11. Riesgo de refinanciación (estructura de fondeo)
#     Financiamiento con Pasivos de Largo Plazo
#=======================================================================================

#---------------------------
# Definición de grupos
#---------------------------
banco_w <- "BANCO W S.A."
pares_bancos <- c("BANCAMIA", "BANCO MUNDO MUJER S.A.")

sector_posibles <- c("Bancos Privados Nacionales", "Bancos Privados")
sector <- intersect(sector_posibles, colnames(base_panel))

if (length(sector) == 0) {
  stop("No se encontró columna de Bancos Privados Nacionales en base_panel.")
}
sector <- sector[1]

#---------------------------
# Construcción de base comparativa de liquidez
#---------------------------
liquidez_comp <- base_panel %>%
  filter(
    Rubro == "APALANCAMIENTO Y RENTABILIDAD",
    Subrubro == "FINANCIAMIENTO CON PASIVOS DE LARGO PLAZO (PASCP-ACTCP / ACTLP)"
  ) %>%
  select(Fecha, all_of(c(banco_w, pares_bancos, sector))) %>%
  mutate(
    Banco_W = as.numeric(str_replace(.data[[banco_w]], ",", ".")),
    Pares = rowMeans(
      cbind(
        as.numeric(str_replace(.data[[pares_bancos[1]]], ",", ".")),
        as.numeric(str_replace(.data[[pares_bancos[2]]], ",", "."))
      ),
      na.rm = TRUE
    ),
    Sector = as.numeric(str_replace(.data[[sector]], ",", "."))
  ) %>%
  select(Fecha, Banco_W, Pares, Sector) %>%
  pivot_longer(
    cols = -Fecha,
    names_to = "Grupo",
    values_to = "Valor"
  ) %>%
  mutate(
    Grupo = factor(
      Grupo,
      levels = c("Banco_W", "Pares", "Sector"),
      labels = c("Banco W S.A.", "Pares (Promedio)", "Bancos Privados Nacionales")
    )
  ) %>%
  arrange(Fecha)


#---------------------------
# Gráfico de riesgo de refinanciación
#---------------------------
graf_liquidez <- ggplot(
  liquidez_comp,
  aes(x = Fecha, y = Valor, color = Grupo)
) +
  geom_line(linewidth = 1.3) +
  geom_point(size = 3) +
  scale_y_continuous(
    labels = scales::percent_format(accuracy = 1)
  ) +
  scale_x_date(
    breaks = sort(unique(liquidez_comp$Fecha)),
    labels = function(x) format(x, "%b-%Y")
  ) +
  scale_color_manual(
    values = c(
      "Banco W S.A." = "#C00000",           # 🔴 Banco W
      "Pares (Promedio)" = "#2F5597",       # 🔵 Pares
      "Bancos Privados Nacionales" = "#7F7F7F" # ⚫ Sector
    )
  ) +
  labs(
    title = "Riesgo de refinanciación (estructura de fondeo)",
    subtitle = "Financiamiento con Pasivos de Largo Plazo (PASCP-ACTCP / ACTLP)",
    x = "Fecha de corte",
    y = "Porcentaje (%)",
    color = ""
  ) +
  tema_banca

print(graf_liquidez)


#=======================================================================================
# 12. RIESGO OPERATIVO
#     Multas, sanciones, litigios e indemnizaciones
#=======================================================================================


#---------------------------
# Definición de grupos
#---------------------------
banco_w <- "BANCO W S.A."
pares_bancos <- c("BANCAMIA", "BANCO MUNDO MUJER S.A.")

sector_posibles <- c("Bancos Privados Nacionales", "Bancos Privados")
sector <- intersect(sector_posibles, colnames(base_panel))

if (length(sector) == 0) {
  stop("No se encontró columna de Bancos Privados Nacionales en base_panel.")
}
sector <- sector[1]

#---------------------------
# Construcción de base de riesgo operativo
#---------------------------
riesgo_operativo_base <- base_panel %>%
  filter(
    Rubro == "GASTOS",
    Subrubro == "MULTAS Y SANCIONES, LITIGIOS, INDEMNIZACIONES Y DEMANDAS-RIESGO OPERATIVO"
  ) %>%
  select(Fecha, all_of(c(banco_w, pares_bancos, sector))) %>%
  mutate(
    Banco_W = as.numeric(str_replace(.data[[banco_w]], ",", ".")),
    Pares = rowMeans(
      cbind(
        as.numeric(str_replace(.data[[pares_bancos[1]]], ",", ".")),
        as.numeric(str_replace(.data[[pares_bancos[2]]], ",", "."))
      ),
      na.rm = TRUE
    ),
    Sector = as.numeric(str_replace(.data[[sector]], ",", "."))
  ) %>%
  select(Fecha, Banco_W, Pares, Sector) %>%
  pivot_longer(
    cols = -Fecha,
    names_to = "Grupo",
    values_to = "Valor"
  ) %>%
  mutate(
    Grupo = factor(
      Grupo,
      levels = c("Banco_W", "Pares", "Sector"),
      labels = c(
        "Banco W S.A.",
        "Pares (Promedio)",
        "Bancos Privados Nacionales"
      )
    )
  ) %>%
  filter(!is.na(Valor)) %>%
  arrange(Fecha)

#---------------------------
# Gráfico de barras con montos reales (YA EN MILLONES)
#---------------------------
graf_riesgo_operativo <- ggplot(
  riesgo_operativo_base,
  aes(
    x = factor(format(Fecha, "%b-%Y")),
    y = Valor,
    fill = Grupo
  )
) +
  geom_col(
    position = position_dodge(width = 0.7),
    width = 0.65
  ) +
  geom_text(
    aes(
      label = paste0(
        format(round(Valor, 1), big.mark = ","),
        " MM"
      )
    ),
    position = position_dodge(width = 0.7),
    vjust = -0.35,
    size = 3.6,
    fontface = "bold",
    color = "black"
  ) +
  scale_fill_manual(
    values = c(
      "Banco W S.A." = "#C00000",
      "Pares (Promedio)" = "#1F4E79",
      "Bancos Privados Nacionales" = "#7F7F7F"
    )
  ) +
  scale_y_continuous(
    labels = comma_format(accuracy = 1),
    expand = expansion(mult = c(0, 0.18))
  ) +
  labs(
    title = "Riesgo Operativo – Multas, Sanciones y Litigios",
    subtitle = "Montos monetarios por período",
    x = "Fecha de corte",
    y = "Millones de COP",
    fill = ""
  ) +
  tema_banca

print(graf_riesgo_operativo)


