Config = {}

-- ======================================
-- !!!! PROIBIDO REVENDA DO SCRIPT !!!!
-- ======================================

-- ========================================
-- LANGUAGE CONFIGURATION
-- ========================================
-- Set your preferred language here
-- Available languages: 'en' (English), 'pt-br' (Portuguese Brazilian)
-- Language files are located in the 'locale/' folder
Config.Language = 'pt-br'

-- Configurações Gerais
Config.UseTarget = false -- Defina como false se não quiser usar ox_target
Config.UseSleeplessInteract = true -- Defina como true para usar sleepless_interact (segunda opção)
Config.DrawDistance = 5.0  -- Desative as duas opções de cima para utilizar o Marker
Config.MarkerDistance = 2.0
Config.DefaultGarage = 'Pillbox Garage Parking' -- Garagem padrão para spawnar veículos 

-- Compatibilidade do Sistema de Chaves
Config.VehicleKeys = 'mri_Qcarkeys' -- Opções: 'qb-vehiclekeys', 'qbx-vehiclekeys', 'mri_Qcarkeys'

-- Webhook do Discord (Opcional)
Config.UseWebhook = true
Config.WebhookURL = '' -- Adicione sua URL do webhook do Discord aqui

-- Descontos VIP
Config.VIPDiscounts = {
    ['zonaoeste'] = 5,  -- 5% de desconto
    ['zonanorte'] = 10, -- 10% de desconto
    ['zonasul'] = 15,   -- 15% de desconto
    ['cristo'] = 20, -- 20% de desconto
    ['reidorio'] = 25, -- 25% de desconto
}

-- Localizações das Concessionárias
Config.DealershipLocations = {
    {
        name = 'Concessionária', -- Change the name of the dealership
        coords = vec3(127.5, -144.11, 54.8),
        heading = 25.0,
        blip = {
            sprite = 326,
            color = 5,
            scale = 0.8,
            label = 'Concessionária' -- Change the label of the dealership on the map
        }
    }
}


-- Vehicle Categories (now handled by translation system)
Config.VehicleCategories = {
    ['compacts'] = 'compacts',
    ['sedans'] = 'sedans',
    ['suvs'] = 'suvs',
    ['coupes'] = 'coupes',
    ['muscle'] = 'muscle',
    ['sports_classics'] = 'sports_classics',
    ['sports'] = 'sports',
    ['super'] = 'super',
    ['motorcycles'] = 'motorcycles',
    ['off_road'] = 'off_road',
    ['industrial'] = 'industrial',
    ['utility'] = 'utility',
    ['vans'] = 'vans',
    ['cycles'] = 'cycles',
    ['boats'] = 'boats',
    ['helicopters'] = 'helicopters',
    ['planes'] = 'planes'
}

-- Veículos Disponíveis   !!! Stock não funcional !!!
Config.Vehicles = {
        -- COMPACTOS (Nível básico: 1-2 semanas de trabalho para novos jogadores)
        { name = 'panto', label = 'Panto', model = 'panto', price = 28000, stock = 1000, img = 'https://docs.fivem.net/vehicles/panto.webp', category = 'compacts', discount = 0, information = {TopSpeed = 155, Braking = 68, Acceleration = 63, Suspension = 73, Handling = 68} },
        { name = 'asbo', label = 'Asbo', model = 'asbo', price = 35000, stock = 1000, img = 'https://docs.fivem.net/vehicles/asbo.webp', category = 'compacts', discount = 0, information = {TopSpeed = 160, Braking = 70, Acceleration = 65, Suspension = 75, Handling = 70} },
        { name = 'club', label = 'Club', model = 'club', price = 38000, stock = 1000, img = 'https://docs.fivem.net/vehicles/club.webp', category = 'compacts', discount = 0, information = {TopSpeed = 162, Braking = 71, Acceleration = 66, Suspension = 76, Handling = 71} },
        { name = 'blista', label = 'Blista', model = 'blista', price = 42000, stock = 1000, img = 'https://docs.fivem.net/vehicles/blista.webp', category = 'compacts', discount = 0, information = {TopSpeed = 165, Braking = 72, Acceleration = 68, Suspension = 76, Handling = 72} },
        { name = 'issi2', label = 'Issi', model = 'issi2', price = 45000, stock = 1000, img = 'https://docs.fivem.net/vehicles/issi2.webp', category = 'compacts', discount = 0, information = {TopSpeed = 163, Braking = 70, Acceleration = 67, Suspension = 75, Handling = 70} },
        { name = 'prairie', label = 'Prairie', model = 'prairie', price = 48000, stock = 1000, img = 'https://docs.fivem.net/vehicles/prairie.webp', category = 'compacts', discount = 0, information = {TopSpeed = 167, Braking = 73, Acceleration = 69, Suspension = 77, Handling = 73} },
        { name = 'dilettante', label = 'Dilettante', model = 'dilettante', price = 52000, stock = 1000, img = 'https://docs.fivem.net/vehicles/dilettante.webp', category = 'compacts', discount = 0, information = {TopSpeed = 158, Braking = 69, Acceleration = 64, Suspension = 74, Handling = 69} },
        { name = 'rhapsody', label = 'Rhapsody', model = 'rhapsody', price = 55000, stock = 1000, img = 'https://docs.fivem.net/vehicles/rhapsody.webp', category = 'compacts', discount = 0, information = {TopSpeed = 169, Braking = 74, Acceleration = 70, Suspension = 78, Handling = 74} },
        { name = 'brioso', label = 'Brioso R/A', model = 'brioso', price = 58000, stock = 1000, img = 'https://docs.fivem.net/vehicles/brioso.webp', category = 'compacts', discount = 0, information = {TopSpeed = 170, Braking = 75, Acceleration = 70, Suspension = 78, Handling = 75} },
        { name = 'brioso2', label = 'Brioso 300', model = 'brioso2', price = 62000, stock = 1000, img = 'https://docs.fivem.net/vehicles/brioso2.webp', category = 'compacts', discount = 0, information = {TopSpeed = 175, Braking = 77, Acceleration = 72, Suspension = 80, Handling = 77} },
        { name = 'weevil', label = 'Weevil', model = 'weevil', price = 68000, stock = 1000, img = 'https://docs.fivem.net/vehicles/weevil.webp', category = 'compacts', discount = 0, information = {TopSpeed = 172, Braking = 76, Acceleration = 71, Suspension = 79, Handling = 76} },
        { name = 'kanjo', label = 'Blista Kanjo', model = 'kanjo', price = 75000, stock = 1000, img = 'https://docs.fivem.net/vehicles/kanjo.webp', category = 'compacts', discount = 0, information = {TopSpeed = 180, Braking = 80, Acceleration = 75, Suspension = 82, Handling = 80} },

        -- SEDÃS (Carros familiares acessíveis: 2-4 semanas de trabalho)
        { name = 'warrener', label = 'Warrener', model = 'warrener', price = 32000, stock = 1000, img = 'https://docs.fivem.net/vehicles/warrener.webp', category = 'sedans', discount = 0, information = {TopSpeed = 183, Braking = 77, Acceleration = 72, Suspension = 79, Handling = 75} },
        { name = 'stanier', label = 'Stanier', model = 'stanier', price = 38000, stock = 1000, img = 'https://docs.fivem.net/vehicles/stanier.webp', category = 'sedans', discount = 0, information = {TopSpeed = 194, Braking = 82, Acceleration = 77, Suspension = 84, Handling = 80} },
        { name = 'stratum', label = 'Stratum', model = 'stratum', price = 42000, stock = 1000, img = 'https://docs.fivem.net/vehicles/stratum.webp', category = 'sedans', discount = 0, information = {TopSpeed = 196, Braking = 82, Acceleration = 77, Suspension = 84, Handling = 80} },
        { name = 'premier', label = 'Premier', model = 'premier', price = 45000, stock = 1000, img = 'https://docs.fivem.net/vehicles/premier.webp', category = 'sedans', discount = 0, information = {TopSpeed = 198, Braking = 83, Acceleration = 78, Suspension = 85, Handling = 81} },
        { name = 'washington', label = 'Washington', model = 'washington', price = 48000, stock = 1000, img = 'https://docs.fivem.net/vehicles/washington.webp', category = 'sedans', discount = 0, information = {TopSpeed = 199, Braking = 83, Acceleration = 78, Suspension = 85, Handling = 81} },
        { name = 'primo', label = 'Primo', model = 'primo', price = 52000, stock = 1000, img = 'https://docs.fivem.net/vehicles/primo.webp', category = 'sedans', discount = 0, information = {TopSpeed = 200, Braking = 84, Acceleration = 79, Suspension = 86, Handling = 82} },
        { name = 'tailgater', label = 'Tailgater', model = 'tailgater', price = 58000, stock = 1000, img = 'https://docs.fivem.net/vehicles/tailgater.webp', category = 'sedans', discount = 0, information = {TopSpeed = 205, Braking = 85, Acceleration = 80, Suspension = 87, Handling = 83} },
        { name = 'sultan', label = 'Sultan', model = 'sultan', price = 68000, stock = 1000, img = 'https://docs.fivem.net/vehicles/sultan.webp', category = 'sedans', discount = 0, information = {TopSpeed = 210, Braking = 87, Acceleration = 82, Suspension = 89, Handling = 85} },
        { name = 'emperor', label = 'Emperor', model = 'emperor', price = 75000, stock = 1000, img = 'https://docs.fivem.net/vehicles/emperor.webp', category = 'sedans', discount = 0, information = {TopSpeed = 180, Braking = 75, Acceleration = 70, Suspension = 78, Handling = 74} },
        { name = 'sultanrs', label = 'Sultan RS', model = 'sultanrs', price = 95000, stock = 1000, img = 'https://docs.fivem.net/vehicles/sultanrs.webp', category = 'sedans', discount = 0, information = {TopSpeed = 230, Braking = 92, Acceleration = 87, Suspension = 94, Handling = 90} },
        { name = 'asea', label = 'Asea', model = 'asea', price = 105000, stock = 1000, img = 'https://docs.fivem.net/vehicles/asea.webp', category = 'sedans', discount = 0, information = {TopSpeed = 190, Braking = 80, Acceleration = 75, Suspension = 82, Handling = 78} },
        { name = 'ingot', label = 'Ingot', model = 'ingot', price = 115000, stock = 1000, img = 'https://docs.fivem.net/vehicles/ingot.webp', category = 'sedans', discount = 0, information = {TopSpeed = 188, Braking = 79, Acceleration = 74, Suspension = 81, Handling = 77} },
        { name = 'glendale', label = 'Glendale', model = 'glendale', price = 125000, stock = 1000, img = 'https://docs.fivem.net/vehicles/glendale.webp', category = 'sedans', discount = 0, information = {TopSpeed = 185, Braking = 78, Acceleration = 73, Suspension = 80, Handling = 76} },
        { name = 'asterope', label = 'Asterope', model = 'asterope', price = 135000, stock = 1000, img = 'https://docs.fivem.net/vehicles/asterope.webp', category = 'sedans', discount = 0, information = {TopSpeed = 195, Braking = 82, Acceleration = 77, Suspension = 84, Handling = 80} },
        { name = 'intruder', label = 'Intruder', model = 'intruder', price = 145000, stock = 1000, img = 'https://docs.fivem.net/vehicles/intruder.webp', category = 'sedans', discount = 0, information = {TopSpeed = 192, Braking = 81, Acceleration = 76, Suspension = 83, Handling = 79} },
        { name = 'fugitive', label = 'Fugitive', model = 'fugitive', price = 185000, stock = 1000, img = 'https://docs.fivem.net/vehicles/fugitive.webp', category = 'sedans', discount = 0, information = {TopSpeed = 200, Braking = 84, Acceleration = 79, Suspension = 86, Handling = 82} },
        { name = 'superd', label = 'Super Diamond', model = 'superd', price = 285000, stock = 1000, img = 'https://docs.fivem.net/vehicles/superd.webp', category = 'sedans', discount = 0, information = {TopSpeed = 215, Braking = 88, Acceleration = 83, Suspension = 90, Handling = 86} },
        { name = 'cinquemila', label = 'Cinquemila', model = 'cinquemila', price = 485000, stock = 1000, img = 'https://docs.fivem.net/vehicles/cinquemila.webp', category = 'sedans', discount = 0, information = {TopSpeed = 220, Braking = 90, Acceleration = 85, Suspension = 92, Handling = 88} },
        { name = 'deity', label = 'Deity', model = 'deity', price = 525000, stock = 1000, img = 'https://docs.fivem.net/vehicles/deity.webp', category = 'sedans', discount = 0, information = {TopSpeed = 225, Braking = 91, Acceleration = 86, Suspension = 93, Handling = 89} },
        { name = 'cognoscenti', label = 'Cognoscenti', model = 'cognoscenti', price = 685000, stock = 1000, img = 'https://docs.fivem.net/vehicles/cognoscenti.webp', category = 'sedans', discount = 0, information = {TopSpeed = 210, Braking = 87, Acceleration = 82, Suspension = 89, Handling = 85} },

        -- SUVS
        { name = 'baller', label = 'Baller', model = 'baller', price = 85000, stock = 1000, img = 'https://docs.fivem.net/vehicles/baller.webp', category = 'suvs', discount = 0, information = {TopSpeed = 205, Braking = 85, Acceleration = 80, Suspension = 90, Handling = 82} },
        { name = 'baller2', label = 'Baller 2', model = 'baller2', price = 95000, stock = 1000, img = 'https://docs.fivem.net/vehicles/baller2.webp', category = 'suvs', discount = 0, information = {TopSpeed = 210, Braking = 87, Acceleration = 82, Suspension = 92, Handling = 84} },
        { name = 'bjxl', label = 'BeeJay XL', model = 'bjxl', price = 65000, stock = 1000, img = 'https://docs.fivem.net/vehicles/bjxl.webp', category = 'suvs', discount = 0, information = {TopSpeed = 195, Braking = 82, Acceleration = 77, Suspension = 88, Handling = 80} },
        { name = 'cavalcade', label = 'Cavalcade', model = 'cavalcade', price = 70000, stock = 1000, img = 'https://docs.fivem.net/vehicles/cavalcade.webp', category = 'suvs', discount = 0, information = {TopSpeed = 200, Braking = 84, Acceleration = 79, Suspension = 89, Handling = 81} },
        { name = 'cavalcade2', label = 'Cavalcade 2', model = 'cavalcade2', price = 75000, stock = 1000, img = 'https://docs.fivem.net/vehicles/cavalcade2.webp', category = 'suvs', discount = 0, information = {TopSpeed = 202, Braking = 84, Acceleration = 79, Suspension = 89, Handling = 81} },
        { name = 'contender', label = 'Contender', model = 'contender', price = 125000, stock = 1000, img = 'https://docs.fivem.net/vehicles/contender.webp', category = 'suvs', discount = 0, information = {TopSpeed = 215, Braking = 88, Acceleration = 83, Suspension = 93, Handling = 85} },
        { name = 'dubsta', label = 'Dubsta', model = 'dubsta', price = 80000, stock = 1000, img = 'https://docs.fivem.net/vehicles/dubsta.webp', category = 'suvs', discount = 0, information = {TopSpeed = 203, Braking = 84, Acceleration = 79, Suspension = 90, Handling = 82} },
        { name = 'fq2', label = 'FQ 2', model = 'fq2', price = 72000, stock = 1000, img = 'https://docs.fivem.net/vehicles/fq2.webp', category = 'suvs', discount = 0, information = {TopSpeed = 198, Braking = 83, Acceleration = 78, Suspension = 88, Handling = 80} },
        { name = 'granger', label = 'Granger', model = 'granger', price = 68000, stock = 1000, img = 'https://docs.fivem.net/vehicles/granger.webp', category = 'suvs', discount = 0, information = {TopSpeed = 197, Braking = 83, Acceleration = 78, Suspension = 88, Handling = 80} },
        { name = 'gresley', label = 'Gresley', model = 'gresley', price = 74000, stock = 1000, img = 'https://docs.fivem.net/vehicles/gresley.webp', category = 'suvs', discount = 0, information = {TopSpeed = 201, Braking = 84, Acceleration = 79, Suspension = 89, Handling = 81} },
        { name = 'habanero', label = 'Habanero', model = 'habanero', price = 78000, stock = 1000, img = 'https://docs.fivem.net/vehicles/habanero.webp', category = 'suvs', discount = 0, information = {TopSpeed = 204, Braking = 85, Acceleration = 80, Suspension = 90, Handling = 82} },
        { name = 'huntley', label = 'Huntley S', model = 'huntley', price = 195000, stock = 1000, img = 'https://docs.fivem.net/vehicles/huntley.webp', category = 'suvs', discount = 0, information = {TopSpeed = 220, Braking = 90, Acceleration = 85, Suspension = 95, Handling = 87} },
        { name = 'landstalker', label = 'Landstalker', model = 'landstalker', price = 58000, stock = 1000, img = 'https://docs.fivem.net/vehicles/landstalker.webp', category = 'suvs', discount = 0, information = {TopSpeed = 192, Braking = 81, Acceleration = 76, Suspension = 87, Handling = 79} },
        { name = 'mesa', label = 'Mesa', model = 'mesa', price = 62000, stock = 1000, img = 'https://docs.fivem.net/vehicles/mesa.webp', category = 'suvs', discount = 0, information = {TopSpeed = 194, Braking = 82, Acceleration = 77, Suspension = 87, Handling = 79} },
        { name = 'patriot', label = 'Patriot', model = 'patriot', price = 135000, stock = 1000, img = 'https://docs.fivem.net/vehicles/patriot.webp', category = 'suvs', discount = 0, information = {TopSpeed = 212, Braking = 87, Acceleration = 82, Suspension = 92, Handling = 84} },
        { name = 'radi', label = 'Radius', model = 'radi', price = 76000, stock = 1000, img = 'https://docs.fivem.net/vehicles/radi.webp', category = 'suvs', discount = 0, information = {TopSpeed = 202, Braking = 84, Acceleration = 79, Suspension = 89, Handling = 81} },
        { name = 'rocoto', label = 'Rocoto', model = 'rocoto', price = 82000, stock = 1000, img = 'https://docs.fivem.net/vehicles/rocoto.webp', category = 'suvs', discount = 0, information = {TopSpeed = 206, Braking = 86, Acceleration = 81, Suspension = 91, Handling = 83} },
        { name = 'seminole', label = 'Seminole', model = 'seminole', price = 64000, stock = 1000, img = 'https://docs.fivem.net/vehicles/seminole.webp', category = 'suvs', discount = 0, information = {TopSpeed = 196, Braking = 82, Acceleration = 77, Suspension = 88, Handling = 80} },
        { name = 'serrano', label = 'Serrano', model = 'serrano', price = 88000, stock = 1000, img = 'https://docs.fivem.net/vehicles/serrano.webp', category = 'suvs', discount = 0, information = {TopSpeed = 208, Braking = 86, Acceleration = 81, Suspension = 91, Handling = 83} },
        { name = 'xls', label = 'XLS', model = 'xls', price = 145000, stock = 1000, img = 'https://docs.fivem.net/vehicles/xls.webp', category = 'suvs', discount = 0, information = {TopSpeed = 218, Braking = 89, Acceleration = 84, Suspension = 94, Handling = 86} },

        -- CUPÊS
        { name = 'cogcabrio', label = 'Cognoscenti Cabrio', model = 'cogcabrio', price = 180000, stock = 1000, img = 'https://docs.fivem.net/vehicles/cogcabrio.webp', category = 'coupes', discount = 0, information = {TopSpeed = 215, Braking = 88, Acceleration = 83, Suspension = 90, Handling = 86} },
        { name = 'exemplar', label = 'Exemplar', model = 'exemplar', price = 205000, stock = 1000, img = 'https://docs.fivem.net/vehicles/exemplar.webp', category = 'coupes', discount = 0, information = {TopSpeed = 220, Braking = 90, Acceleration = 85, Suspension = 92, Handling = 88} },
        { name = 'f620', label = 'F620', model = 'f620', price = 135000, stock = 1000, img = 'https://docs.fivem.net/vehicles/f620.webp', category = 'coupes', discount = 0, information = {TopSpeed = 210, Braking = 87, Acceleration = 82, Suspension = 89, Handling = 85} },
        { name = 'felon', label = 'Felon', model = 'felon', price = 95000, stock = 1000, img = 'https://docs.fivem.net/vehicles/felon.webp', category = 'coupes', discount = 0, information = {TopSpeed = 205, Braking = 85, Acceleration = 80, Suspension = 87, Handling = 83} },
        { name = 'felon2', label = 'Felon GT', model = 'felon2', price = 105000, stock = 1000, img = 'https://docs.fivem.net/vehicles/felon2.webp', category = 'coupes', discount = 0, information = {TopSpeed = 208, Braking = 86, Acceleration = 81, Suspension = 88, Handling = 84} },
        { name = 'jackal', label = 'Jackal', model = 'jackal', price = 78000, stock = 1000, img = 'https://docs.fivem.net/vehicles/jackal.webp', category = 'coupes', discount = 0, information = {TopSpeed = 200, Braking = 84, Acceleration = 79, Suspension = 86, Handling = 82} },
        { name = 'oracle', label = 'Oracle', model = 'oracle', price = 85000, stock = 1000, img = 'https://docs.fivem.net/vehicles/oracle.webp', category = 'coupes', discount = 0, information = {TopSpeed = 203, Braking = 84, Acceleration = 79, Suspension = 86, Handling = 82} },
        { name = 'oracle2', label = 'Oracle XS', model = 'oracle2', price = 92000, stock = 1000, img = 'https://docs.fivem.net/vehicles/oracle2.webp', category = 'coupes', discount = 0, information = {TopSpeed = 206, Braking = 85, Acceleration = 80, Suspension = 87, Handling = 83} },
        { name = 'sentinel', label = 'Sentinel', model = 'sentinel', price = 98000, stock = 1000, img = 'https://docs.fivem.net/vehicles/sentinel.webp', category = 'coupes', discount = 0, information = {TopSpeed = 207, Braking = 86, Acceleration = 81, Suspension = 88, Handling = 84} },
        { name = 'sentinel2', label = 'Sentinel XS', model = 'sentinel2', price = 115000, stock = 1000, img = 'https://docs.fivem.net/vehicles/sentinel2.webp', category = 'coupes', discount = 0, information = {TopSpeed = 212, Braking = 87, Acceleration = 82, Suspension = 89, Handling = 85} },
        { name = 'windsor', label = 'Windsor', model = 'windsor', price = 845000, stock = 1000, img = 'https://docs.fivem.net/vehicles/windsor.webp', category = 'coupes', discount = 0, information = {TopSpeed = 230, Braking = 92, Acceleration = 87, Suspension = 94, Handling = 90} },
        { name = 'windsor2', label = 'Windsor Drop', model = 'windsor2', price = 900000, stock = 1000, img = 'https://docs.fivem.net/vehicles/windsor2.webp', category = 'coupes', discount = 0, information = {TopSpeed = 235, Braking = 93, Acceleration = 88, Suspension = 95, Handling = 91} },
        { name = 'zion', label = 'Zion', model = 'zion', price = 88000, stock = 1000, img = 'https://docs.fivem.net/vehicles/zion.webp', category = 'coupes', discount = 0, information = {TopSpeed = 204, Braking = 85, Acceleration = 80, Suspension = 87, Handling = 83} },
        { name = 'zion2', label = 'Zion Cabrio', model = 'zion2', price = 95000, stock = 1000, img = 'https://docs.fivem.net/vehicles/zion2.webp', category = 'coupes', discount = 0, information = {TopSpeed = 206, Braking = 85, Acceleration = 80, Suspension = 87, Handling = 83} },

-- MUSCLE CARS
        { name = 'blade', label = 'Blade', model = 'blade', price = 95000, stock = 1000, img = 'https://docs.fivem.net/vehicles/blade.webp', category = 'muscle', discount = 0, information = {TopSpeed = 210, Braking = 85, Acceleration = 82, Suspension = 84, Handling = 80} },
        { name = 'buccaneer', label = 'Buccaneer', model = 'buccaneer', price = 85000, stock = 1000, img = 'https://docs.fivem.net/vehicles/buccaneer.webp', category = 'muscle', discount = 0, information = {TopSpeed = 205, Braking = 83, Acceleration = 80, Suspension = 82, Handling = 78} },
        { name = 'buccaneer2', label = 'Buccaneer Custom', model = 'buccaneer2', price = 125000, stock = 1000, img = 'https://docs.fivem.net/vehicles/buccaneer2.webp', category = 'muscle', discount = 0, information = {TopSpeed = 218, Braking = 87, Acceleration = 84, Suspension = 86, Handling = 82} },
        { name = 'chino', label = 'Chino', model = 'chino', price = 78000, stock = 1000, img = 'https://docs.fivem.net/vehicles/chino.webp', category = 'muscle', discount = 0, information = {TopSpeed = 200, Braking = 82, Acceleration = 78, Suspension = 80, Handling = 76} },
        { name = 'chino2', label = 'Chino Custom', model = 'chino2', price = 115000, stock = 1000, img = 'https://docs.fivem.net/vehicles/chino2.webp', category = 'muscle', discount = 0, information = {TopSpeed = 215, Braking = 86, Acceleration = 82, Suspension = 84, Handling = 80} },
        { name = 'clique', label = 'Clique', model = 'clique', price = 365000, stock = 1000, img = 'https://docs.fivem.net/vehicles/clique.webp', category = 'muscle', discount = 0, information = {TopSpeed = 225, Braking = 89, Acceleration = 85, Suspension = 87, Handling = 83} },
        { name = 'coquette3', label = 'Coquette BlackFin', model = 'coquette3', price = 195000, stock = 1000, img = 'https://docs.fivem.net/vehicles/coquette3.webp', category = 'muscle', discount = 0, information = {TopSpeed = 220, Braking = 88, Acceleration = 84, Suspension = 86, Handling = 82} },
        { name = 'deviant', label = 'Deviant', model = 'deviant', price = 512000, stock = 1000, img = 'https://docs.fivem.net/vehicles/deviant.webp', category = 'muscle', discount = 0, information = {TopSpeed = 235, Braking = 92, Acceleration = 88, Suspension = 90, Handling = 86} },
        { name = 'dominator', label = 'Dominator', model = 'dominator', price = 95000, stock = 1000, img = 'https://docs.fivem.net/vehicles/dominator.webp', category = 'muscle', discount = 0, information = {TopSpeed = 212, Braking = 86, Acceleration = 82, Suspension = 84, Handling = 80} },
        { name = 'dominator2', label = 'Pisswasser Dominator', model = 'dominator2', price = 145000, stock = 1000, img = 'https://docs.fivem.net/vehicles/dominator2.webp', category = 'muscle', discount = 0, information = {TopSpeed = 218, Braking = 87, Acceleration = 84, Suspension = 86, Handling = 82} },
        { name = 'dukes', label = 'Dukes', model = 'dukes', price = 62000, stock = 1000, img = 'https://docs.fivem.net/vehicles/dukes.webp', category = 'muscle', discount = 0, information = {TopSpeed = 208, Braking = 84, Acceleration = 80, Suspension = 82, Handling = 78} },
        { name = 'gauntlet', label = 'Gauntlet', model = 'gauntlet', price = 105000, stock = 1000, img = 'https://docs.fivem.net/vehicles/gauntlet.webp', category = 'muscle', discount = 0, information = {TopSpeed = 215, Braking = 87, Acceleration = 83, Suspension = 85, Handling = 81} },
        { name = 'gauntlet2', label = 'Gauntlet Redwood', model = 'gauntlet2', price = 135000, stock = 1000, img = 'https://docs.fivem.net/vehicles/gauntlet2.webp', category = 'muscle', discount = 0, information = {TopSpeed = 220, Braking = 88, Acceleration = 84, Suspension = 86, Handling = 82} },
        { name = 'hermes', label = 'Hermes', model = 'hermes', price = 535000, stock = 1000, img = 'https://docs.fivem.net/vehicles/hermes.webp', category = 'muscle', discount = 0, information = {TopSpeed = 228, Braking = 90, Acceleration = 86, Suspension = 88, Handling = 84} },
        { name = 'hotknife', label = 'Hotknife', model = 'hotknife', price = 90000, stock = 1000, img = 'https://docs.fivem.net/vehicles/hotknife.webp', category = 'muscle', discount = 0, information = {TopSpeed = 210, Braking = 85, Acceleration = 82, Suspension = 84, Handling = 80} },
        { name = 'faction', label = 'Faction', model = 'faction', price = 88000, stock = 1000, img = 'https://docs.fivem.net/vehicles/faction.webp', category = 'muscle', discount = 0, information = {TopSpeed = 207, Braking = 84, Acceleration = 80, Suspension = 82, Handling = 78} },
        { name = 'faction2', label = 'Faction Custom', model = 'faction2', price = 118000, stock = 1000, img = 'https://docs.fivem.net/vehicles/faction2.webp', category = 'muscle', discount = 0, information = {TopSpeed = 217, Braking = 87, Acceleration = 83, Suspension = 85, Handling = 81} },
        { name = 'moonbeam', label = 'Moonbeam', model = 'moonbeam', price = 85000, stock = 1000, img = 'https://docs.fivem.net/vehicles/moonbeam.webp', category = 'muscle', discount = 0, information = {TopSpeed = 202, Braking = 82, Acceleration = 78, Suspension = 80, Handling = 76} },
        { name = 'moonbeam2', label = 'Moonbeam Custom', model = 'moonbeam2', price = 115000, stock = 1000, img = 'https://docs.fivem.net/vehicles/moonbeam2.webp', category = 'muscle', discount = 0, information = {TopSpeed = 212, Braking = 85, Acceleration = 81, Suspension = 83, Handling = 79} },
        { name = 'nightshade', label = 'Nightshade', model = 'nightshade', price = 585000, stock = 1000, img = 'https://docs.fivem.net/vehicles/nightshade.webp', category = 'muscle', discount = 0, information = {TopSpeed = 232, Braking = 91, Acceleration = 87, Suspension = 89, Handling = 85} },
        { name = 'phoenix', label = 'Phoenix', model = 'phoenix', price = 92000, stock = 1000, img = 'https://docs.fivem.net/vehicles/phoenix.webp', category = 'muscle', discount = 0, information = {TopSpeed = 209, Braking = 85, Acceleration = 81, Suspension = 83, Handling = 79} },
        { name = 'picador', label = 'Picador', model = 'picador', price = 68000, stock = 1000, img = 'https://docs.fivem.net/vehicles/picador.webp', category = 'muscle', discount = 0, information = {TopSpeed = 205, Braking = 83, Acceleration = 79, Suspension = 81, Handling = 77} },
        { name = 'ratloader', label = 'Rat-Loader', model = 'ratloader', price = 38000, stock = 1000, img = 'https://docs.fivem.net/vehicles/ratloader.webp', category = 'muscle', discount = 0, information = {TopSpeed = 185, Braking = 78, Acceleration = 74, Suspension = 76, Handling = 72} },
        { name = 'ratloader2', label = 'Rat-Truck', model = 'ratloader2', price = 45000, stock = 1000, img = 'https://docs.fivem.net/vehicles/ratloader2.webp', category = 'muscle', discount = 0, information = {TopSpeed = 190, Braking = 80, Acceleration = 76, Suspension = 78, Handling = 74} },
        { name = 'ruiner', label = 'Ruiner', model = 'ruiner', price = 98000, stock = 1000, img = 'https://docs.fivem.net/vehicles/ruiner.webp', category = 'muscle', discount = 0, information = {TopSpeed = 211, Braking = 86, Acceleration = 82, Suspension = 84, Handling = 80} },
        { name = 'sabregt', label = 'Sabre Turbo', model = 'sabregt', price = 105000, stock = 1000, img = 'https://docs.fivem.net/vehicles/sabregt.webp', category = 'muscle', discount = 0, information = {TopSpeed = 214, Braking = 86, Acceleration = 82, Suspension = 84, Handling = 80} },
        { name = 'sabregt2', label = 'Sabre Turbo Custom', model = 'sabregt2', price = 135000, stock = 1000, img = 'https://docs.fivem.net/vehicles/sabregt2.webp', category = 'muscle', discount = 0, information = {TopSpeed = 224, Braking = 89, Acceleration = 85, Suspension = 87, Handling = 83} },
        { name = 'slamvan', label = 'Slamvan', model = 'slamvan', price = 78000, stock = 1000, img = 'https://docs.fivem.net/vehicles/slamvan.webp', category = 'muscle', discount = 0, information = {TopSpeed = 198, Braking = 81, Acceleration = 77, Suspension = 79, Handling = 75} },
        { name = 'slamvan2', label = 'Lost Slamvan', model = 'slamvan2', price = 88000, stock = 1000, img = 'https://docs.fivem.net/vehicles/slamvan2.webp', category = 'muscle', discount = 0, information = {TopSpeed = 203, Braking = 82, Acceleration = 78, Suspension = 80, Handling = 76} },
        { name = 'slamvan3', label = 'Slamvan Custom', model = 'slamvan3', price = 118000, stock = 1000, img = 'https://docs.fivem.net/vehicles/slamvan3.webp', category = 'muscle', discount = 0, information = {TopSpeed = 213, Braking = 85, Acceleration = 81, Suspension = 83, Handling = 79} },
        { name = 'stalion', label = 'Stallion', model = 'stalion', price = 95000, stock = 1000, img = 'https://docs.fivem.net/vehicles/stalion.webp', category = 'muscle', discount = 0, information = {TopSpeed = 210, Braking = 85, Acceleration = 81, Suspension = 83, Handling = 79} },
        { name = 'stalion2', label = 'Burger Shot Stallion', model = 'stalion2', price = 125000, stock = 1000, img = 'https://docs.fivem.net/vehicles/stalion2.webp', category = 'muscle', discount = 0, information = {TopSpeed = 215, Braking = 87, Acceleration = 83, Suspension = 85, Handling = 81} },
        { name = 'tampa', label = 'Tampa', model = 'tampa', price = 375000, stock = 1000, img = 'https://docs.fivem.net/vehicles/tampa.webp', category = 'muscle', discount = 0, information = {TopSpeed = 228, Braking = 90, Acceleration = 86, Suspension = 88, Handling = 84} },
        { name = 'vigero', label = 'Vigero', model = 'vigero', price = 105000, stock = 1000, img = 'https://docs.fivem.net/vehicles/vigero.webp', category = 'muscle', discount = 0, information = {TopSpeed = 213, Braking = 86, Acceleration = 82, Suspension = 84, Handling = 80} },
        { name = 'virgo', label = 'Virgo', model = 'virgo', price = 195000, stock = 1000, img = 'https://docs.fivem.net/vehicles/virgo.webp', category = 'muscle', discount = 0, information = {TopSpeed = 220, Braking = 88, Acceleration = 84, Suspension = 86, Handling = 82} },
        { name = 'virgo2', label = 'Virgo Classic Custom', model = 'virgo2', price = 235000, stock = 1000, img = 'https://docs.fivem.net/vehicles/virgo2.webp', category = 'muscle', discount = 0, information = {TopSpeed = 225, Braking = 89, Acceleration = 85, Suspension = 87, Handling = 83} },
        { name = 'voodoo', label = 'Voodoo', model = 'voodoo', price = 88000, stock = 1000, img = 'https://docs.fivem.net/vehicles/voodoo.webp', category = 'muscle', discount = 0, information = {TopSpeed = 206, Braking = 84, Acceleration = 80, Suspension = 82, Handling = 78} },
        { name = 'voodoo2', label = 'Voodoo Custom', model = 'voodoo2', price = 118000, stock = 1000, img = 'https://docs.fivem.net/vehicles/voodoo2.webp', category = 'muscle', discount = 0, information = {TopSpeed = 216, Braking = 87, Acceleration = 83, Suspension = 85, Handling = 81} },
        { name = 'yosemite', label = 'Yosemite', model = 'yosemite', price = 485000, stock = 1000, img = 'https://docs.fivem.net/vehicles/yosemite.webp', category = 'muscle', discount = 0, information = {TopSpeed = 231, Braking = 91, Acceleration = 87, Suspension = 89, Handling = 85} },

        -- ESPORTIVOS CLÁSSICOS
        { name = 'casco', label = 'Casco', model = 'casco', price = 680000, stock = 1000, img = 'https://docs.fivem.net/vehicles/casco.webp', category = 'sportsclassics', discount = 0, information = {TopSpeed = 235, Braking = 91, Acceleration = 86, Suspension = 88, Handling = 84} },
        { name = 'coquette2', label = 'Coquette Classic', model = 'coquette2', price = 665000, stock = 1000, img = 'https://docs.fivem.net/vehicles/coquette2.webp', category = 'sportsclassics', discount = 0, information = {TopSpeed = 238, Braking = 92, Acceleration = 87, Suspension = 89, Handling = 85} },
        { name = 'monroe', label = 'Monroe', model = 'monroe', price = 490000, stock = 1000, img = 'https://docs.fivem.net/vehicles/monroe.webp', category = 'sportsclassics', discount = 0, information = {TopSpeed = 232, Braking = 90, Acceleration = 85, Suspension = 87, Handling = 83} },
        { name = 'stinger', label = 'Stinger', model = 'stinger', price = 850000, stock = 1000, img = 'https://docs.fivem.net/vehicles/stinger.webp', category = 'sportsclassics', discount = 0, information = {TopSpeed = 242, Braking = 92, Acceleration = 87, Suspension = 89, Handling = 85} },
        { name = 'z190', label = 'Z190', model = 'z190', price = 900000, stock = 1000, img = 'https://docs.fivem.net/vehicles/z190.webp', category = 'sportsclassics', discount = 0, information = {TopSpeed = 246, Braking = 93, Acceleration = 88, Suspension = 90, Handling = 86} },

        -- ESPORTIVOS (Carros de performance: 1-3 meses de trabalho para profissionais)
        { name = 'elegy', label = 'Elegy RH8', model = 'elegy', price = 125000, stock = 1000, img = 'https://docs.fivem.net/vehicles/elegy.webp', category = 'sports', discount = 0, information = {TopSpeed = 233, Braking = 90, Acceleration = 85, Suspension = 87, Handling = 83} },
        { name = 'banshee', label = 'Banshee', model = 'banshee', price = 145000, stock = 1000, img = 'https://docs.fivem.net/vehicles/banshee.webp', category = 'sports', discount = 0, information = {TopSpeed = 240, Braking = 92, Acceleration = 87, Suspension = 89, Handling = 85} },
        { name = 'surano', label = 'Surano', model = 'surano', price = 165000, stock = 1000, img = 'https://docs.fivem.net/vehicles/surano.webp', category = 'sports', discount = 0, information = {TopSpeed = 235, Braking = 91, Acceleration = 86, Suspension = 88, Handling = 84} },
        { name = 'ninef', label = '9F', model = 'ninef', price = 185000, stock = 1000, img = 'https://docs.fivem.net/vehicles/ninef.webp', category = 'sports', discount = 0, information = {TopSpeed = 237, Braking = 91, Acceleration = 86, Suspension = 88, Handling = 84} },
        { name = 'feltzer2', label = 'Feltzer', model = 'feltzer2', price = 205000, stock = 1000, img = 'https://docs.fivem.net/vehicles/feltzer2.webp', category = 'sports', discount = 0, information = {TopSpeed = 239, Braking = 92, Acceleration = 87, Suspension = 89, Handling = 85} },
        { name = 'rapidgt', label = 'Rapid GT', model = 'rapidgt', price = 225000, stock = 1000, img = 'https://docs.fivem.net/vehicles/rapidgt.webp', category = 'sports', discount = 0, information = {TopSpeed = 240, Braking = 92, Acceleration = 87, Suspension = 89, Handling = 85} },
        { name = 'coquette', label = 'Coquette', model = 'coquette', price = 245000, stock = 1000, img = 'https://docs.fivem.net/vehicles/coquette.webp', category = 'sports', discount = 0, information = {TopSpeed = 236, Braking = 91, Acceleration = 86, Suspension = 88, Handling = 84} },
        { name = 'carbonizzare', label = 'Carbonizzare', model = 'carbonizzare', price = 285000, stock = 1000, img = 'https://docs.fivem.net/vehicles/carbonizzare.webp', category = 'sports', discount = 0, information = {TopSpeed = 242, Braking = 92, Acceleration = 87, Suspension = 89, Handling = 85} },
        { name = 'jester', label = 'Jester', model = 'jester', price = 325000, stock = 1000, img = 'https://docs.fivem.net/vehicles/jester.webp', category = 'sports', discount = 0, information = {TopSpeed = 243, Braking = 93, Acceleration = 88, Suspension = 90, Handling = 86} },

        -- SUPER CARROS (Ultra luxo: 3-6 meses de economia dedicada para liderança)
        { name = 'voltic', label = 'Voltic', model = 'voltic', price = 485000, stock = 1000, img = 'https://docs.fivem.net/vehicles/voltic.webp', category = 'super', discount = 0, information = {TopSpeed = 250, Braking = 95, Acceleration = 90, Suspension = 93, Handling = 89} },
        { name = 'bullet', label = 'Bullet', model = 'bullet', price = 525000, stock = 1000, img = 'https://docs.fivem.net/vehicles/bullet.webp', category = 'super', discount = 0, information = {TopSpeed = 245, Braking = 93, Acceleration = 88, Suspension = 90, Handling = 86} },
        { name = 'vacca', label = 'Vacca', model = 'vacca', price = 685000, stock = 1000, img = 'https://docs.fivem.net/vehicles/vacca.webp', category = 'super', discount = 0, information = {TopSpeed = 243, Braking = 93, Acceleration = 88, Suspension = 90, Handling = 86} },
        { name = 'infernus', label = 'Infernus', model = 'infernus', price = 825000, stock = 1000, img = 'https://docs.fivem.net/vehicles/infernus.webp', category = 'super', discount = 0, information = {TopSpeed = 245, Braking = 93, Acceleration = 88, Suspension = 90, Handling = 86} },
        { name = 'turismor', label = 'Turismo R', model = 'turismor', price = 1125000, stock = 1000, img = 'https://docs.fivem.net/vehicles/turismor.webp', category = 'super', discount = 0, information = {TopSpeed = 248, Braking = 94, Acceleration = 89, Suspension = 92, Handling = 88} },
        { name = 'banshee2', label = 'Banshee 900R', model = 'banshee2', price = 1385000, stock = 1000, img = 'https://docs.fivem.net/vehicles/banshee2.webp', category = 'super', discount = 0, information = {TopSpeed = 252, Braking = 95, Acceleration = 90, Suspension = 93, Handling = 89} },
        { name = 'cheetah', label = 'Cheetah', model = 'cheetah', price = 1685000, stock = 1000, img = 'https://docs.fivem.net/vehicles/cheetah.webp', category = 'super', discount = 0, information = {TopSpeed = 250, Braking = 94, Acceleration = 89, Suspension = 91, Handling = 87} },
        { name = 'zentorno', label = 'Zentorno', model = 'zentorno', price = 1985000, stock = 1000, img = 'https://docs.fivem.net/vehicles/zentorno.webp', category = 'super', discount = 0, information = {TopSpeed = 251, Braking = 95, Acceleration = 90, Suspension = 93, Handling = 89} },
        { name = 'entityxf', label = 'Entity XF', model = 'entityxf', price = 2285000, stock = 1000, img = 'https://docs.fivem.net/vehicles/entityxf.webp', category = 'super', discount = 0, information = {TopSpeed = 248, Braking = 94, Acceleration = 89, Suspension = 92, Handling = 88} },
        { name = 'adder', label = 'Adder', model = 'adder', price = 2685000, stock = 1000, img = 'https://docs.fivem.net/vehicles/adder.webp', category = 'super', discount = 0, information = {TopSpeed = 250, Braking = 95, Acceleration = 90, Suspension = 95, Handling = 88} },
        { name = 'pfister811', label = 'Pfister 811', model = 'pfister811', price = 3185000, stock = 1000, img = 'https://docs.fivem.net/vehicles/pfister811.webp', category = 'super', discount = 0, information = {TopSpeed = 252, Braking = 95, Acceleration = 90, Suspension = 93, Handling = 89} },
        { name = 'italigtb', label = 'Itali GTB', model = 'italigtb', price = 3485000, stock = 1000, img = 'https://docs.fivem.net/vehicles/italigtb.webp', category = 'super', discount = 0, information = {TopSpeed = 254, Braking = 96, Acceleration = 91, Suspension = 94, Handling = 90} },
        { name = 'gp1', label = 'GP1', model = 'gp1', price = 3785000, stock = 1000, img = 'https://docs.fivem.net/vehicles/gp1.webp', category = 'super', discount = 0, information = {TopSpeed = 253, Braking = 95, Acceleration = 90, Suspension = 93, Handling = 89} },
        { name = 'tempesta', label = 'Tempesta', model = 'tempesta', price = 4185000, stock = 1000, img = 'https://docs.fivem.net/vehicles/tempesta.webp', category = 'super', discount = 0, information = {TopSpeed = 255, Braking = 96, Acceleration = 91, Suspension = 94, Handling = 90} },
        { name = 'nero', label = 'Nero', model = 'nero', price = 4685000, stock = 1000, img = 'https://docs.fivem.net/vehicles/nero.webp', category = 'super', discount = 0, information = {TopSpeed = 256, Braking = 96, Acceleration = 91, Suspension = 94, Handling = 90} },
        { name = 'reaper', label = 'Reaper', model = 'reaper', price = 5185000, stock = 1000, img = 'https://docs.fivem.net/vehicles/reaper.webp', category = 'super', discount = 0, information = {TopSpeed = 257, Braking = 97, Acceleration = 92, Suspension = 95, Handling = 91} },
        { name = 'fmj', label = 'FMJ', model = 'fmj', price = 5685000, stock = 1000, img = 'https://docs.fivem.net/vehicles/fmj.webp', category = 'super', discount = 0, information = {TopSpeed = 255, Braking = 96, Acceleration = 91, Suspension = 94, Handling = 90} },
        { name = 'cyclone', label = 'Cyclone', model = 'cyclone', price = 6285000, stock = 1000, img = 'https://docs.fivem.net/vehicles/cyclone.webp', category = 'super', discount = 0, information = {TopSpeed = 258, Braking = 97, Acceleration = 92, Suspension = 95, Handling = 91} },
        { name = 'osiris', label = 'Osiris', model = 'osiris', price = 6785000, stock = 1000, img = 'https://docs.fivem.net/vehicles/osiris.webp', category = 'super', discount = 0, information = {TopSpeed = 259, Braking = 97, Acceleration = 92, Suspension = 95, Handling = 91} },
        { name = 'visione', label = 'Visione', model = 'visione', price = 7385000, stock = 1000, img = 'https://docs.fivem.net/vehicles/visione.webp', category = 'super', discount = 0, information = {TopSpeed = 261, Braking = 98, Acceleration = 93, Suspension = 96, Handling = 92} },
        { name = 't20', label = 'T20', model = 't20', price = 7985000, stock = 1000, img = 'https://docs.fivem.net/vehicles/t20.webp', category = 'super', discount = 0, information = {TopSpeed = 262, Braking = 98, Acceleration = 93, Suspension = 96, Handling = 92} },
        { name = 'autarch', label = 'Autarch', model = 'autarch', price = 8685000, stock = 1000, img = 'https://docs.fivem.net/vehicles/autarch.webp', category = 'super', discount = 0, information = {TopSpeed = 260, Braking = 98, Acceleration = 93, Suspension = 96, Handling = 92} },
        { name = 'tyrus', label = 'Tyrus', model = 'tyrus', price = 9485000, stock = 1000, img = 'https://docs.fivem.net/vehicles/tyrus.webp', category = 'super', discount = 0, information = {TopSpeed = 263, Braking = 98, Acceleration = 93, Suspension = 96, Handling = 92} },

        -- MOTOCICLETAS (Transporte acessível: 1-4 semanas de trabalho)
        { name = 'pcj', label = 'PCJ 600', model = 'pcj', price = 8500, stock = 1000, img = 'https://docs.fivem.net/vehicles/pcj.webp', category = 'motorcycles', discount = 0, information = {TopSpeed = 195, Braking = 82, Acceleration = 77, Suspension = 79, Handling = 75} },
        { name = 'ruffian', label = 'Ruffian', model = 'ruffian', price = 9500, stock = 1000, img = 'https://docs.fivem.net/vehicles/ruffian.webp', category = 'motorcycles', discount = 0, information = {TopSpeed = 192, Braking = 81, Acceleration = 76, Suspension = 78, Handling = 74} },
        { name = 'faggio', label = 'Faggio', model = 'faggio', price = 12000, stock = 1000, img = 'https://docs.fivem.net/vehicles/faggio.webp', category = 'motorcycles', discount = 0, information = {TopSpeed = 120, Braking = 60, Acceleration = 55, Suspension = 57, Handling = 53} },
        { name = 'nemesis', label = 'Nemesis', model = 'nemesis', price = 14500, stock = 1000, img = 'https://docs.fivem.net/vehicles/nemesis.webp', category = 'motorcycles', discount = 0, information = {TopSpeed = 198, Braking = 83, Acceleration = 78, Suspension = 80, Handling = 76} },
        { name = 'hexer', label = 'Hexer', model = 'hexer', price = 16500, stock = 1000, img = 'https://docs.fivem.net/vehicles/hexer.webp', category = 'motorcycles', discount = 0, information = {TopSpeed = 188, Braking = 80, Acceleration = 75, Suspension = 77, Handling = 73} },
        { name = 'sanchez', label = 'Sanchez', model = 'sanchez', price = 18500, stock = 1000, img = 'https://docs.fivem.net/vehicles/sanchez.webp', category = 'motorcycles', discount = 0, information = {TopSpeed = 185, Braking = 78, Acceleration = 73, Suspension = 75, Handling = 71} },
        { name = 'vader', label = 'Vader', model = 'vader', price = 22000, stock = 1000, img = 'https://docs.fivem.net/vehicles/vader.webp', category = 'motorcycles', discount = 0, information = {TopSpeed = 202, Braking = 84, Acceleration = 79, Suspension = 81, Handling = 77} },
        { name = 'double', label = 'Double T', model = 'double', price = 28000, stock = 1000, img = 'https://docs.fivem.net/vehicles/double.webp', category = 'motorcycles', discount = 0, information = {TopSpeed = 200, Braking = 84, Acceleration = 79, Suspension = 81, Handling = 77} },
        { name = 'bati', label = 'Bati 801', model = 'bati', price = 38000, stock = 1000, img = 'https://docs.fivem.net/vehicles/bati.webp', category = 'motorcycles', discount = 0, information = {TopSpeed = 215, Braking = 87, Acceleration = 82, Suspension = 84, Handling = 80} },
        { name = 'bagger', label = 'Bagger', model = 'bagger', price = 42000, stock = 1000, img = 'https://docs.fivem.net/vehicles/bagger.webp', category = 'motorcycles', discount = 0, information = {TopSpeed = 185, Braking = 78, Acceleration = 73, Suspension = 75, Handling = 71} },
        { name = 'bati2', label = 'Bati 801RR', model = 'bati2', price = 48000, stock = 1000, img = 'https://docs.fivem.net/vehicles/bati2.webp', category = 'motorcycles', discount = 0, information = {TopSpeed = 218, Braking = 88, Acceleration = 83, Suspension = 85, Handling = 81} },
        { name = 'daemon', label = 'Daemon', model = 'daemon', price = 55000, stock = 1000, img = 'https://docs.fivem.net/vehicles/daemon.webp', category = 'motorcycles', discount = 0, information = {TopSpeed = 195, Braking = 82, Acceleration = 77, Suspension = 79, Handling = 75} },
        { name = 'thrust', label = 'Thrust', model = 'thrust', price = 68000, stock = 1000, img = 'https://docs.fivem.net/vehicles/thrust.webp', category = 'motorcycles', discount = 0, information = {TopSpeed = 218, Braking = 88, Acceleration = 83, Suspension = 85, Handling = 81} },
        { name = 'hakuchou', label = 'Hakuchou', model = 'hakuchou', price = 85000, stock = 1000, img = 'https://docs.fivem.net/vehicles/hakuchou.webp', category = 'motorcycles', discount = 0, information = {TopSpeed = 228, Braking = 91, Acceleration = 86, Suspension = 88, Handling = 84} },
        { name = 'innovation', label = 'Innovation', model = 'innovation', price = 95000, stock = 1000, img = 'https://docs.fivem.net/vehicles/innovation.webp', category = 'motorcycles', discount = 0, information = {TopSpeed = 215, Braking = 87, Acceleration = 82, Suspension = 84, Handling = 80} },
        { name = 'sovereign', label = 'Sovereign', model = 'sovereign', price = 105000, stock = 1000, img = 'https://docs.fivem.net/vehicles/sovereign.webp', category = 'motorcycles', discount = 0, information = {TopSpeed = 210, Braking = 85, Acceleration = 80, Suspension = 82, Handling = 78} },
        { name = 'akuma', label = 'Akuma', model = 'akuma', price = 115000, stock = 1000, img = 'https://docs.fivem.net/vehicles/akuma.webp', category = 'motorcycles', discount = 0, information = {TopSpeed = 210, Braking = 85, Acceleration = 80, Suspension = 82, Handling = 78} },
        { name = 'gargoyle', label = 'Gargoyle', model = 'gargoyle', price = 125000, stock = 1000, img = 'https://docs.fivem.net/vehicles/gargoyle.webp', category = 'motorcycles', discount = 0, information = {TopSpeed = 220, Braking = 88, Acceleration = 83, Suspension = 85, Handling = 81} },
        { name = 'carbonrs', label = 'Carbon RS', model = 'carbonrs', price = 135000, stock = 1000, img = 'https://docs.fivem.net/vehicles/carbonrs.webp', category = 'motorcycles', discount = 0, information = {TopSpeed = 212, Braking = 86, Acceleration = 81, Suspension = 83, Handling = 79} },
        { name = 'enduro', label = 'Enduro', model = 'enduro', price = 155000, stock = 1000, img = 'https://docs.fivem.net/vehicles/enduro.webp', category = 'motorcycles', discount = 0, information = {TopSpeed = 205, Braking = 85, Acceleration = 80, Suspension = 82, Handling = 78} },
        { name = 'zombiea', label = 'Zombie Bobber', model = 'zombiea', price = 185000, stock = 1000, img = 'https://docs.fivem.net/vehicles/zombiea.webp', category = 'motorcycles', discount = 0, information = {TopSpeed = 208, Braking = 85, Acceleration = 80, Suspension = 82, Handling = 78} },
        { name = 'zombieb', label = 'Zombie Chopper', model = 'zombieb', price = 215000, stock = 1000, img = 'https://docs.fivem.net/vehicles/zombieb.webp', category = 'motorcycles', discount = 0, information = {TopSpeed = 212, Braking = 86, Acceleration = 81, Suspension = 83, Handling = 79} },
        { name = 'bf400', label = 'BF400', model = 'bf400', price = 285000, stock = 1000, img = 'https://docs.fivem.net/vehicles/bf400.webp', category = 'motorcycles', discount = 0, information = {TopSpeed = 225, Braking = 90, Acceleration = 85, Suspension = 87, Handling = 83} },
        { name = 'vortex', label = 'Vortex', model = 'vortex', price = 385000, stock = 1000, img = 'https://docs.fivem.net/vehicles/vortex.webp', category = 'motorcycles', discount = 0, information = {TopSpeed = 230, Braking = 91, Acceleration = 86, Suspension = 88, Handling = 84} },
        { name = 'vindicator', label = 'Vindicator', model = 'vindicator', price = 485000, stock = 1000, img = 'https://docs.fivem.net/vehicles/vindicator.webp', category = 'motorcycles', discount = 0, information = {TopSpeed = 235, Braking = 93, Acceleration = 88, Suspension = 90, Handling = 86} },
        { name = 'cliffhanger', label = 'Cliffhanger', model = 'cliffhanger', price = 585000, stock = 1000, img = 'https://docs.fivem.net/vehicles/cliffhanger.webp', category = 'motorcycles', discount = 0, information = {TopSpeed = 230, Braking = 92, Acceleration = 87, Suspension = 89, Handling = 85} },
        { name = 'lectro', label = 'Lectro', model = 'lectro', price = 685000, stock = 1000, img = 'https://docs.fivem.net/vehicles/lectro.webp', category = 'motorcycles', discount = 0, information = {TopSpeed = 232, Braking = 92, Acceleration = 87, Suspension = 89, Handling = 85} },
        { name = 'hakuchou2', label = 'Hakuchou Drag', model = 'hakuchou2', price = 885000, stock = 1000, img = 'https://docs.fivem.net/vehicles/hakuchou2.webp', category = 'motorcycles', discount = 0, information = {TopSpeed = 240, Braking = 95, Acceleration = 90, Suspension = 92, Handling = 88} },
        { name = 'defiler', label = 'Defiler', model = 'defiler', price = 1185000, stock = 1000, img = 'https://docs.fivem.net/vehicles/defiler.webp', category = 'motorcycles', discount = 0, information = {TopSpeed = 235, Braking = 94, Acceleration = 89, Suspension = 91, Handling = 87} },

        -- OFF-ROAD
        { name = 'bfinjection', label = 'BF Injection', model = 'bfinjection', price = 16000, stock = 1000, img = 'https://docs.fivem.net/vehicles/bfinjection.webp', category = 'offroad', discount = 0, information = {TopSpeed = 165, Braking = 72, Acceleration = 67, Suspension = 85, Handling = 73} },
        { name = 'bifta', label = 'Bifta', model = 'bifta', price = 75000, stock = 1000, img = 'https://docs.fivem.net/vehicles/bifta.webp', category = 'offroad', discount = 0, information = {TopSpeed = 180, Braking = 78, Acceleration = 73, Suspension = 90, Handling = 79} },
        { name = 'blazer', label = 'Blazer', model = 'blazer', price = 8000, stock = 1000, img = 'https://docs.fivem.net/vehicles/blazer.webp', category = 'offroad', discount = 0, information = {TopSpeed = 140, Braking = 65, Acceleration = 60, Suspension = 82, Handling = 66} },
        { name = 'blazer4', label = 'Blazer Aqua', model = 'blazer4', price = 1755600, stock = 1000, img = 'https://docs.fivem.net/vehicles/blazer4.webp', category = 'offroad', discount = 0, information = {TopSpeed = 155, Braking = 70, Acceleration = 65, Suspension = 85, Handling = 71} },
        { name = 'bodhi2', label = 'Bodhi', model = 'bodhi2', price = 56000, stock = 1000, img = 'https://docs.fivem.net/vehicles/bodhi2.webp', category = 'offroad', discount = 0, information = {TopSpeed = 170, Braking = 75, Acceleration = 70, Suspension = 88, Handling = 76} },
        { name = 'brawler', label = 'Brawler', model = 'brawler', price = 715000, stock = 1000, img = 'https://docs.fivem.net/vehicles/brawler.webp', category = 'offroad', discount = 0, information = {TopSpeed = 195, Braking = 85, Acceleration = 80, Suspension = 92, Handling = 82} },
        { name = 'dloader', label = 'Duneloader', model = 'dloader', price = 135000, stock = 1000, img = 'https://docs.fivem.net/vehicles/dloader.webp', category = 'offroad', discount = 0, information = {TopSpeed = 175, Braking = 76, Acceleration = 71, Suspension = 89, Handling = 77} },
        { name = 'dubsta3', label = 'Dubsta 6x6', model = 'dubsta3', price = 249000, stock = 1000, img = 'https://docs.fivem.net/vehicles/dubsta3.webp', category = 'offroad', discount = 0, information = {TopSpeed = 185, Braking = 80, Acceleration = 75, Suspension = 91, Handling = 79} },
        { name = 'dune', label = 'Dune Buggy', model = 'dune', price = 20000, stock = 1000, img = 'https://docs.fivem.net/vehicles/dune.webp', category = 'offroad', discount = 0, information = {TopSpeed = 160, Braking = 70, Acceleration = 65, Suspension = 84, Handling = 70} },
        { name = 'kalahari', label = 'Kalahari', model = 'kalahari', price = 40000, stock = 1000, img = 'https://docs.fivem.net/vehicles/kalahari.webp', category = 'offroad', discount = 0, information = {TopSpeed = 165, Braking = 72, Acceleration = 67, Suspension = 85, Handling = 73} },
        { name = 'mesa3', label = 'Mesa (Merryweather)', model = 'mesa3', price = 87000, stock = 1000, img = 'https://docs.fivem.net/vehicles/mesa3.webp', category = 'offroad', discount = 0, information = {TopSpeed = 178, Braking = 77, Acceleration = 72, Suspension = 88, Handling = 78} },
        { name = 'rancherxl', label = 'Rancher XL', model = 'rancherxl', price = 59000, stock = 1000, img = 'https://docs.fivem.net/vehicles/rancherxl.webp', category = 'offroad', discount = 0, information = {TopSpeed = 172, Braking = 74, Acceleration = 69, Suspension = 87, Handling = 75} },
        { name = 'rebel', label = 'Rebel', model = 'rebel', price = 22000, stock = 1000, img = 'https://docs.fivem.net/vehicles/rebel.webp', category = 'offroad', discount = 0, information = {TopSpeed = 168, Braking = 73, Acceleration = 68, Suspension = 86, Handling = 74} },
        { name = 'rebel2', label = 'Rusty Rebel', model = 'rebel2', price = 18000, stock = 1000, img = 'https://docs.fivem.net/vehicles/rebel2.webp', category = 'offroad', discount = 0, information = {TopSpeed = 165, Braking = 72, Acceleration = 67, Suspension = 85, Handling = 73} },
        { name = 'riata', label = 'Riata', model = 'riata', price = 380000, stock = 1000, img = 'https://docs.fivem.net/vehicles/riata.webp', category = 'offroad', discount = 0, information = {TopSpeed = 182, Braking = 79, Acceleration = 74, Suspension = 89, Handling = 80} },
        { name = 'sandking', label = 'Sandking XL', model = 'sandking', price = 38000, stock = 1000, img = 'https://docs.fivem.net/vehicles/sandking.webp', category = 'offroad', discount = 0, information = {TopSpeed = 175, Braking = 76, Acceleration = 71, Suspension = 88, Handling = 77} },
        { name = 'sandking2', label = 'Sandking SWB', model = 'sandking2', price = 42000, stock = 1000, img = 'https://docs.fivem.net/vehicles/sandking2.webp', category = 'offroad', discount = 0, information = {TopSpeed = 178, Braking = 77, Acceleration = 72, Suspension = 89, Handling = 78} },
        { name = 'trophytruck', label = 'Trophy Truck', model = 'trophytruck', price = 550000, stock = 1000, img = 'https://docs.fivem.net/vehicles/trophytruck.webp', category = 'offroad', discount = 0, information = {TopSpeed = 190, Braking = 83, Acceleration = 78, Suspension = 92, Handling = 84} },
        { name = 'trophytruck2', label = 'Desert Raid', model = 'trophytruck2', price = 695000, stock = 1000, img = 'https://docs.fivem.net/vehicles/trophytruck2.webp', category = 'offroad', discount = 0, information = {TopSpeed = 195, Braking = 85, Acceleration = 80, Suspension = 93, Handling = 86} },
}



-- Sistema de Visualização de Veículos
Config.PreviewLocation = vector4(797.25, -3000.18, -69.63 - 1, 242.65) -- Onde o jogador fica durante a visualização  (Não mexer)
Config.PreviewVehicleSpawn = vector4(797.25, -3000.18, -69.63 - 1, 242.65) -- Onde o veículo de visualização spawna

-- Configuração do Test Drive
Config.TestDrive = {
    Location = vec4(-2729.9, 3264.43, 32.81, 237.88), -- Local do test drive (topo das Vinewood Hills)
    Duration = 60, -- Duração do test drive em segundos (1 minuto)
    ReturnKey = 22, -- Tecla ESPAÇO para retornar mais cedo
    Blip = {
        sprite = 315,
        color = 5,
        scale = 0.8,
        label = 'Área de Test Drive'
    }
}

-- Sistema de Entrega de Veículos (onde o jogador spawna com o veículo comprado)
Config.DeliveryLocation = vec4(136.43, -121.04, 54.8, 69.45) -- Local de spawn do jogador após compra
Config.DeliveryVehicleSpawn = vec4(136.43, -121.04, 54.8, 69.45) -- Local de spawn do veículo após compra

-- Trabalhos de Admin (Quem pode acessar o menu admin) (Não foi criado!!)
Config.AdminJobs = {
    'admin',
    'dealer',
    'manager'
}

-- Veículos de Exposição do Showroom (Opcional - para fins de exibição)
Config.ShowroomVehicles = {
    {
        model = 'comet6',
        coords = vec4(125.84, -157.44, 54.79 - 1, 311.37)
    },
    {
        model = 'emerus',
        coords = vector4(134.04, -160.7, 54.79 - 1, 335.0)
    },
    {
        model = 'entity2',
        coords = vector4(142.23, -163.59, 54.79 - 1, 11.98)
    },
    {
        model = 'skyline',
        coords = vector4(113.57, -146.62, 60.76 - 1, 271.12)
    },
    {
        model = 'ngtn20',
        coords = vector4(118.61, -154.07, 60.7 - 1, 344.11)
    }
} 