/**
 * Catálogo de categorias de serviço — CÓPIA de
 * assets/data/service_categories.json (o app lê de lá). Usado só pelo hub,
 * pra escolher a categoria ao liberar o teste grátis de quem ainda é só
 * cliente (ver testeGratis.ts). Se mudar o JSON do app, gere de novo.
 */
export interface CategoriaServico {
  id: string;
  label: string;
  grupo: string;
}

export const CATEGORIAS: CategoriaServico[] = [
  {
    "id": "pedreiro",
    "label": "Pedreiro / Alvenaria",
    "grupo": "Casa e Construção"
  },
  {
    "id": "azulejista",
    "label": "Azulejista / Revestimentos",
    "grupo": "Casa e Construção"
  },
  {
    "id": "gesseiro",
    "label": "Gesseiro / Drywall",
    "grupo": "Casa e Construção"
  },
  {
    "id": "telhadista",
    "label": "Telhados e Calhas",
    "grupo": "Casa e Construção"
  },
  {
    "id": "impermeabilizacao",
    "label": "Impermeabilização",
    "grupo": "Casa e Construção"
  },
  {
    "id": "fundacao",
    "label": "Fundação e Estrutura",
    "grupo": "Casa e Construção"
  },
  {
    "id": "reforma_geral",
    "label": "Reforma Geral",
    "grupo": "Casa e Construção"
  },
  {
    "id": "cacambeiro",
    "label": "Caçamba de Entulho / Caçambeiro",
    "grupo": "Casa e Construção"
  },
  {
    "id": "tele_entulho",
    "label": "Tele-entulho / Remoção de Entulho",
    "grupo": "Casa e Construção"
  },
  {
    "id": "construcao_civil",
    "label": "Construção Civil / Engenheiro",
    "grupo": "Casa e Construção"
  },
  {
    "id": "arquiteto",
    "label": "Arquiteto",
    "grupo": "Casa e Construção"
  },
  {
    "id": "mestre_obras",
    "label": "Mestre de Obras",
    "grupo": "Casa e Construção"
  },
  {
    "id": "pisos",
    "label": "Instalação de Pisos e Laminados",
    "grupo": "Casa e Construção"
  },
  {
    "id": "vidraceiro",
    "label": "Vidraçaria",
    "grupo": "Casa e Construção"
  },
  {
    "id": "marmore_granito",
    "label": "Marmoraria / Granito",
    "grupo": "Casa e Construção"
  },
  {
    "id": "esquadrias",
    "label": "Esquadrias de Alumínio",
    "grupo": "Casa e Construção"
  },
  {
    "id": "eletricista",
    "label": "Eletricista",
    "grupo": "Manutenção e Reparos"
  },
  {
    "id": "encanador",
    "label": "Encanador",
    "grupo": "Manutenção e Reparos"
  },
  {
    "id": "serralheiro",
    "label": "Serralheiro",
    "grupo": "Manutenção e Reparos"
  },
  {
    "id": "pintor",
    "label": "Pintor",
    "grupo": "Manutenção e Reparos"
  },
  {
    "id": "chaveiro",
    "label": "Chaveiro",
    "grupo": "Manutenção e Reparos"
  },
  {
    "id": "dedetizador",
    "label": "Dedetização / Controle de Pragas",
    "grupo": "Manutenção e Reparos"
  },
  {
    "id": "antenista",
    "label": "Antenas e TV por Assinatura",
    "grupo": "Manutenção e Reparos"
  },
  {
    "id": "alarme_seguranca",
    "label": "Instalação de Alarmes e Câmeras",
    "grupo": "Manutenção e Reparos"
  },
  {
    "id": "reparo_geral",
    "label": "Marido de Aluguel / Reparos Gerais",
    "grupo": "Manutenção e Reparos"
  },
  {
    "id": "gas",
    "label": "Instalador de Gás",
    "grupo": "Manutenção e Reparos"
  },
  {
    "id": "manutencao_predial",
    "label": "Manutenção Predial",
    "grupo": "Manutenção e Reparos"
  },
  {
    "id": "contador",
    "label": "Contador",
    "grupo": "Manutenção e Reparos"
  },
  {
    "id": "despachante",
    "label": "Despachante",
    "grupo": "Manutenção e Reparos"
  },
  {
    "id": "portao_eletronico",
    "label": "Portões Eletrônicos",
    "grupo": "Manutenção e Reparos"
  },
  {
    "id": "interfone",
    "label": "Interfone e Portaria",
    "grupo": "Manutenção e Reparos"
  },
  {
    "id": "climatizacao",
    "label": "Técnico de Ar-condicionado",
    "grupo": "Climatização e Eletrodomésticos"
  },
  {
    "id": "refrigeracao",
    "label": "Refrigeração / Geladeiras e Freezers",
    "grupo": "Climatização e Eletrodomésticos"
  },
  {
    "id": "maquina_lavar",
    "label": "Conserto de Máquina de Lavar",
    "grupo": "Climatização e Eletrodomésticos"
  },
  {
    "id": "fogao_forno",
    "label": "Conserto de Fogão e Forno",
    "grupo": "Climatização e Eletrodomésticos"
  },
  {
    "id": "eletrodomesticos_geral",
    "label": "Conserto de Eletrodomésticos em Geral",
    "grupo": "Climatização e Eletrodomésticos"
  },
  {
    "id": "aquecedor",
    "label": "Aquecedor de Água / Boiler",
    "grupo": "Climatização e Eletrodomésticos"
  },
  {
    "id": "exaustor_coifa",
    "label": "Exaustor e Coifa",
    "grupo": "Climatização e Eletrodomésticos"
  },
  {
    "id": "ventilacao",
    "label": "Ventilação Industrial",
    "grupo": "Climatização e Eletrodomésticos"
  },
  {
    "id": "purificador_agua",
    "label": "Purificador de Água",
    "grupo": "Climatização e Eletrodomésticos"
  },
  {
    "id": "jardineiro",
    "label": "Jardineiro",
    "grupo": "Jardim e Áreas Externas"
  },
  {
    "id": "paisagismo",
    "label": "Paisagismo",
    "grupo": "Jardim e Áreas Externas"
  },
  {
    "id": "poda_arvores",
    "label": "Poda de Árvores",
    "grupo": "Jardim e Áreas Externas"
  },
  {
    "id": "piscina",
    "label": "Manutenção de Piscina",
    "grupo": "Jardim e Áreas Externas"
  },
  {
    "id": "irrigacao",
    "label": "Sistemas de Irrigação",
    "grupo": "Jardim e Áreas Externas"
  },
  {
    "id": "gramado",
    "label": "Plantio e Manutenção de Gramado",
    "grupo": "Jardim e Áreas Externas"
  },
  {
    "id": "cerca_muro",
    "label": "Cercas e Muros",
    "grupo": "Jardim e Áreas Externas"
  },
  {
    "id": "dedetizacao_jardim",
    "label": "Controle de Pragas em Jardim",
    "grupo": "Jardim e Áreas Externas"
  },
  {
    "id": "horta",
    "label": "Horta Urbana",
    "grupo": "Jardim e Áreas Externas"
  },
  {
    "id": "mecanico",
    "label": "Mecânico Automotivo",
    "grupo": "Automóveis"
  },
  {
    "id": "eletricista_auto",
    "label": "Eletricista Automotivo",
    "grupo": "Automóveis"
  },
  {
    "id": "funilaria",
    "label": "Funilaria e Pintura",
    "grupo": "Automóveis"
  },
  {
    "id": "lavagem_auto",
    "label": "Lava-rápido / Estética Automotiva",
    "grupo": "Automóveis"
  },
  {
    "id": "borracheiro",
    "label": "Borracheiro",
    "grupo": "Automóveis"
  },
  {
    "id": "guincho",
    "label": "Guincho / Reboque",
    "grupo": "Automóveis"
  },
  {
    "id": "instalador_som",
    "label": "Instalação de Som e Acessórios",
    "grupo": "Automóveis"
  },
  {
    "id": "vidraceiro_auto",
    "label": "Vidraçaria Automotiva",
    "grupo": "Automóveis"
  },
  {
    "id": "moto_mecanico",
    "label": "Mecânico de Motos",
    "grupo": "Automóveis"
  },
  {
    "id": "revisao_veicular",
    "label": "Revisão Veicular",
    "grupo": "Automóveis"
  },
  {
    "id": "chaveiro_automotivo",
    "label": "Chaveiro Automotivo",
    "grupo": "Automóveis"
  },
  {
    "id": "limpeza",
    "label": "Diarista",
    "grupo": "Limpeza e Serviços Domésticos"
  },
  {
    "id": "limpeza_pos_obra",
    "label": "Limpeza Pós-obra",
    "grupo": "Limpeza e Serviços Domésticos"
  },
  {
    "id": "passadeira",
    "label": "Passadeira de Roupas",
    "grupo": "Limpeza e Serviços Domésticos"
  },
  {
    "id": "cozinheira",
    "label": "Cozinheira Particular",
    "grupo": "Limpeza e Serviços Domésticos"
  },
  {
    "id": "organizadora",
    "label": "Organizadora de Ambientes",
    "grupo": "Limpeza e Serviços Domésticos"
  },
  {
    "id": "limpeza_estofados",
    "label": "Limpeza de Estofados e Tapetes",
    "grupo": "Limpeza e Serviços Domésticos"
  },
  {
    "id": "limpeza_vidros",
    "label": "Limpeza de Vidros e Fachadas",
    "grupo": "Limpeza e Serviços Domésticos"
  },
  {
    "id": "baba",
    "label": "Babá",
    "grupo": "Limpeza e Serviços Domésticos"
  },
  {
    "id": "cuidador_idosos",
    "label": "Cuidador de Idosos",
    "grupo": "Limpeza e Serviços Domésticos"
  },
  {
    "id": "lavanderia",
    "label": "Lavanderia a Domicílio",
    "grupo": "Limpeza e Serviços Domésticos"
  },
  {
    "id": "tecnico_informatica",
    "label": "Técnico de Informática",
    "grupo": "Tecnologia"
  },
  {
    "id": "tecnico_celular",
    "label": "Assistência Técnica de Celular",
    "grupo": "Tecnologia"
  },
  {
    "id": "redes_wifi",
    "label": "Instalação de Redes e Wi-Fi",
    "grupo": "Tecnologia"
  },
  {
    "id": "desenvolvedor",
    "label": "Desenvolvedor de Sistemas / Apps",
    "grupo": "Tecnologia"
  },
  {
    "id": "suporte_ti",
    "label": "Suporte de TI",
    "grupo": "Tecnologia"
  },
  {
    "id": "design_grafico",
    "label": "Design Gráfico",
    "grupo": "Tecnologia"
  },
  {
    "id": "marketing_digital",
    "label": "Marketing Digital",
    "grupo": "Tecnologia"
  },
  {
    "id": "cftv",
    "label": "Instalação de Câmeras / CFTV",
    "grupo": "Tecnologia"
  },
  {
    "id": "social_media",
    "label": "Gestão de Redes Sociais",
    "grupo": "Tecnologia"
  },
  {
    "id": "mudanca",
    "label": "Mudanças Residenciais",
    "grupo": "Mudanças e Transporte"
  },
  {
    "id": "frete",
    "label": "Frete e Carreto",
    "grupo": "Mudanças e Transporte"
  },
  {
    "id": "motoboy",
    "label": "Motoboy",
    "grupo": "Mudanças e Transporte"
  },
  {
    "id": "transporte_escolar",
    "label": "Transporte Escolar",
    "grupo": "Mudanças e Transporte"
  },
  {
    "id": "transporte_cargas",
    "label": "Transporte de Cargas",
    "grupo": "Mudanças e Transporte"
  },
  {
    "id": "embalagem_mudanca",
    "label": "Embalagem para Mudança",
    "grupo": "Mudanças e Transporte"
  },
  {
    "id": "marceneiro",
    "label": "Marceneiro",
    "grupo": "Móveis e Decoração"
  },
  {
    "id": "montador_moveis",
    "label": "Montador de Móveis",
    "grupo": "Móveis e Decoração"
  },
  {
    "id": "estofador",
    "label": "Estofador",
    "grupo": "Móveis e Decoração"
  },
  {
    "id": "decorador",
    "label": "Decorador de Interiores",
    "grupo": "Móveis e Decoração"
  },
  {
    "id": "tapeceiro",
    "label": "Tapeceiro",
    "grupo": "Móveis e Decoração"
  },
  {
    "id": "cortineiro",
    "label": "Instalador de Cortinas e Persianas",
    "grupo": "Móveis e Decoração"
  },
  {
    "id": "restaurador_moveis",
    "label": "Restaurador de Móveis",
    "grupo": "Móveis e Decoração"
  },
  {
    "id": "vitral",
    "label": "Vitral e Vidro Decorativo",
    "grupo": "Móveis e Decoração"
  },
  {
    "id": "advogado",
    "label": "Advogado",
    "grupo": "Serviços Profissionais"
  },
  {
    "id": "contabilidade",
    "label": "Consultoria Contábil",
    "grupo": "Serviços Profissionais"
  },
  {
    "id": "traducao",
    "label": "Tradutor / Intérprete",
    "grupo": "Serviços Profissionais"
  },
  {
    "id": "consultoria_financeira",
    "label": "Consultoria Financeira",
    "grupo": "Serviços Profissionais"
  },
  {
    "id": "fotografo",
    "label": "Fotógrafo Profissional",
    "grupo": "Serviços Profissionais"
  },
  {
    "id": "videomaker",
    "label": "Videomaker",
    "grupo": "Serviços Profissionais"
  },
  {
    "id": "professor_particular",
    "label": "Professor Particular / Aulas",
    "grupo": "Serviços Profissionais"
  },
  {
    "id": "personal_trainer",
    "label": "Personal Trainer",
    "grupo": "Serviços Profissionais"
  },
  {
    "id": "psicologo",
    "label": "Psicólogo",
    "grupo": "Serviços Profissionais"
  },
  {
    "id": "nutricionista",
    "label": "Nutricionista",
    "grupo": "Serviços Profissionais"
  },
  {
    "id": "corretor_imoveis",
    "label": "Corretor de Imóveis",
    "grupo": "Serviços Profissionais"
  },
  {
    "id": "buffet",
    "label": "Buffet",
    "grupo": "Eventos"
  },
  {
    "id": "dj",
    "label": "DJ",
    "grupo": "Eventos"
  },
  {
    "id": "fotografo_eventos",
    "label": "Fotografia para Eventos",
    "grupo": "Eventos"
  },
  {
    "id": "decoracao_festas",
    "label": "Decoração de Festas",
    "grupo": "Eventos"
  },
  {
    "id": "garcom",
    "label": "Garçom / Recepcionista",
    "grupo": "Eventos"
  },
  {
    "id": "cerimonialista",
    "label": "Cerimonialista",
    "grupo": "Eventos"
  },
  {
    "id": "som_luz_eventos",
    "label": "Som e Iluminação para Eventos",
    "grupo": "Eventos"
  },
  {
    "id": "confeiteira",
    "label": "Confeiteira / Doces para Festas",
    "grupo": "Eventos"
  },
  {
    "id": "aluguel_estruturas",
    "label": "Aluguel de Estruturas e Mobiliário",
    "grupo": "Eventos"
  },
  {
    "id": "cabeleireiro",
    "label": "Cabeleireiro",
    "grupo": "Beleza e Bem-estar"
  },
  {
    "id": "manicure",
    "label": "Manicure e Pedicure",
    "grupo": "Beleza e Bem-estar"
  },
  {
    "id": "maquiadora",
    "label": "Maquiadora",
    "grupo": "Beleza e Bem-estar"
  },
  {
    "id": "esteticista",
    "label": "Esteticista",
    "grupo": "Beleza e Bem-estar"
  },
  {
    "id": "massagista",
    "label": "Massagista",
    "grupo": "Beleza e Bem-estar"
  },
  {
    "id": "barbeiro",
    "label": "Barbeiro",
    "grupo": "Beleza e Bem-estar"
  },
  {
    "id": "depilacao",
    "label": "Depilação",
    "grupo": "Beleza e Bem-estar"
  },
  {
    "id": "designer_sobrancelhas",
    "label": "Designer de Sobrancelhas",
    "grupo": "Beleza e Bem-estar"
  },
  {
    "id": "spa_domicilio",
    "label": "Spa a Domicílio",
    "grupo": "Beleza e Bem-estar"
  },
  {
    "id": "veterinario",
    "label": "Veterinário",
    "grupo": "Serviços para Animais"
  },
  {
    "id": "banho_tosa",
    "label": "Banho e Tosa",
    "grupo": "Serviços para Animais"
  },
  {
    "id": "adestrador",
    "label": "Adestrador de Cães",
    "grupo": "Serviços para Animais"
  },
  {
    "id": "dog_walker",
    "label": "Dog Walker / Passeador",
    "grupo": "Serviços para Animais"
  },
  {
    "id": "pet_sitter",
    "label": "Pet Sitter / Hospedagem",
    "grupo": "Serviços para Animais"
  },
  {
    "id": "petshop_domicilio",
    "label": "Petshop a Domicílio",
    "grupo": "Serviços para Animais"
  }
];
